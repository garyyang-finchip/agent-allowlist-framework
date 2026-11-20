// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AWFRegistry} from "../assets/erc-9999/contracts/AWFRegistry.sol";
import {AWFGuard} from "../assets/erc-9999/contracts/AWFGuard.sol";
import {AWFExampleConsumer} from "../assets/erc-9999/contracts/examples/AWFExampleConsumer.sol";
import {IAWFRegistry} from "../assets/erc-9999/contracts/interfaces/IAWFRegistry.sol";
import {IAWFGuard} from "../assets/erc-9999/contracts/interfaces/IAWFGuard.sol";
import {IAWFEvaluator} from "../assets/erc-9999/contracts/interfaces/IAWFEvaluator.sol";
import {IAWFRelationSource} from "../assets/erc-9999/contracts/interfaces/IAWFRelationSource.sol";
import "../assets/erc-9999/contracts/interfaces/AWFTypes.sol";
import {IdentityFixture} from "./fixtures/IdentityFixture.sol";

/// @dev Evaluator whose answer is set by the test.
contract ScriptedEvaluator is IAWFEvaluator {
    Match public result;
    bytes32 public reason = "SCRIPTED";
    uint64 public validUntil = type(uint64).max;
    bytes32 public config = keccak256("config/1");
    uint8 public fault; // 1 revert, 2 never return, 3 out-of-range result, 4 wrong return size

    function set(Match result_) external {
        result = result_;
    }

    function setValidUntil(uint64 validUntil_) external {
        validUntil = validUntil_;
    }

    function setConfig(bytes32 config_) external {
        config = config_;
    }

    function setFault(uint8 fault_) external {
        fault = fault_;
    }

    function configHash() external view returns (bytes32) {
        return config;
    }

    function evaluate(bytes32, bytes32, SubjectRef calldata, Request calldata, bytes calldata)
        external
        view
        returns (Match, bytes32, uint64, bytes32)
    {
        if (fault == 1) revert("fault");
        if (fault == 2) {
            uint256 x;
            while (true) x += 1;
        }
        if (fault == 3) {
            assembly {
                mstore(0x00, 7)
                mstore(0x20, 0)
                mstore(0x40, 0)
                mstore(0x60, 0)
                return(0x00, 0x80)
            }
        }
        if (fault == 4) {
            assembly {
                mstore(0x00, 1)
                return(0x00, 0x20)
            }
        }
        return (result, reason, validUntil, bytes32(0));
    }
}

/// @dev Relation source whose origins are set by the test.
contract ScriptedRelation is IAWFRelationSource {
    bytes32 public constant RELATION = keccak256("test.relation");

    mapping(bytes32 => SubjectRef[]) private _origins;
    mapping(bytes32 => bool) private _open; // the enumeration never ends
    bool public broken;

    function relate(SubjectRef calldata origin, SubjectRef calldata subject) external {
        _origins[_key(subject)].push(origin);
    }

    function setOpen(SubjectRef calldata subject, bool open) external {
        _open[_key(subject)] = open;
    }

    function setBroken(bool broken_) external {
        broken = broken_;
    }

    function configHash() external pure returns (bytes32) {
        return keccak256("relation/1");
    }

    function originOf(bytes32 relationType, SubjectRef calldata subject, bytes calldata, uint256 index)
        external
        view
        returns (uint8 status, SubjectRef memory origin, uint64 since)
    {
        require(!broken, "broken");
        if (relationType != RELATION) return (0, origin, 0);
        SubjectRef[] storage list = _origins[_key(subject)];
        if (index < list.length) return (1, list[index], 1);
        return (_open[_key(subject)] ? 0 : 2, origin, 0);
    }

    function _key(SubjectRef calldata s) private pure returns (bytes32) {
        return keccak256(abi.encode(s.kind, s.chainId, s.namespace, s.id));
    }
}

/// @dev Builds the committed sets of the specification.
library SetTree {
    function leaf(uint256 index, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(SET_LEAF_TAG, index, key));
    }

    function build(bytes32[] memory keys) internal pure returns (bytes32[][] memory levels) {
        uint256 depth;
        while ((uint256(1) << depth) < keys.length) ++depth;
        levels = new bytes32[][](depth + 1);
        levels[0] = new bytes32[](uint256(1) << depth);
        for (uint256 i; i < keys.length; ++i) levels[0][i] = leaf(i, keys[i]);
        for (uint256 l = 1; l <= depth; ++l) {
            levels[l] = new bytes32[](levels[l - 1].length / 2);
            for (uint256 j; j < levels[l].length; ++j) {
                levels[l][j] = keccak256(abi.encode(levels[l - 1][2 * j], levels[l - 1][2 * j + 1]));
            }
        }
    }

    function root(bytes32[][] memory levels) internal pure returns (bytes32) {
        return levels[levels.length - 1][0];
    }

    function path(bytes32[][] memory levels, uint256 index) internal pure returns (bytes32[] memory p) {
        p = new bytes32[](levels.length - 1);
        for (uint256 l; l < p.length; ++l) {
            p[l] = levels[l][index ^ 1];
            index >>= 1;
        }
    }

    function memberProof(bytes32[][] memory levels, uint256 index) internal pure returns (bytes memory) {
        SetProof memory p;
        p.member = true;
        p.index = index;
        p.path = path(levels, index);
        return abi.encode(p);
    }

    /// @dev `low` is the index of the greatest key below the absent one.
    function absenceProof(bytes32[][] memory levels, bytes32[] memory keys, uint256 low)
        internal
        pure
        returns (bytes memory)
    {
        SetProof memory p;
        p.index = low;
        p.path = path(levels, low);
        p.lowKey = keys[low];
        p.highKey = keys[low + 1];
        p.highPath = path(levels, low + 1);
        return abi.encode(p);
    }
}

abstract contract AWFBase is Test {
    AWFRegistry internal registry;
    AWFGuard internal guard;
    AWFExampleConsumer internal venue;
    IdentityFixture internal identities;

    address internal manager = makeAddr("manager");
    address internal adopter = makeAddr("adopter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal mallory = makeAddr("mallory");

    bytes32 internal constant JOIN = keccak256("awf.action.join");
    bytes32 internal constant BID = keccak256("awf.action.bid");
    bytes32 internal constant INVOKE = keccak256("awf.action.invoke");
    bytes32 internal constant CONTEXT = keccak256("context/1");
    uint256 internal constant T0 = 1_800_000_000;

    uint256 private _salt;

    function setUp() public virtual {
        vm.warp(T0);
        registry = new AWFRegistry();
        guard = new AWFGuard();
        identities = new IdentityFixture();
        vm.prank(adopter);
        venue = new AWFExampleConsumer(guard, "venue");
    }

    // ------------------------------------------------------------ subjects

    function _account(address a) internal view returns (SubjectRef memory) {
        return SubjectRef(KIND_ACCOUNT, block.chainid, address(0), bytes32(uint256(uint160(a))));
    }

    function _entry(address namespace, uint256 id) internal view returns (SubjectRef memory) {
        return SubjectRef(KIND_ENTRY, block.chainid, namespace, bytes32(id));
    }

    function _artefact(bytes32 digest) internal pure returns (SubjectRef memory) {
        return SubjectRef(KIND_DIGEST, 0, address(0), digest);
    }

    function _key(SubjectRef memory s) internal pure returns (bytes32) {
        return keccak256(abi.encode(s.kind, s.chainId, s.namespace, s.id));
    }

    // ------------------------------------------------------------ lists

    function _listConfig(Polarity polarity, Mode mode) internal returns (ListConfig memory c) {
        c.polarity = polarity;
        c.mode = mode;
        c.salt = bytes32(++_salt);
    }

    function _list(Polarity polarity) internal returns (bytes32 listId) {
        ListConfig memory c = _listConfig(polarity, Mode.ENUMERATED);
        vm.prank(manager);
        listId = registry.createList(c, "");
    }

    function _predicateList(Polarity polarity, address evaluator) internal returns (bytes32 listId) {
        bytes32 criteriaId = registry.registerCriteria(keccak256("criteria"), evaluator, bytes32(0), 0, "");
        ListConfig memory c = _listConfig(polarity, Mode.PREDICATE);
        c.criteriaId = criteriaId;
        vm.prank(manager);
        listId = registry.createList(c, "");
    }

    function _derivedList(bytes32 source, bytes32 criteriaId, bytes32 pin) internal returns (bytes32 listId) {
        ListConfig memory c = _listConfig(registry.listOf(source).polarity, Mode.DERIVED);
        c.source = source;
        c.sourcePin = pin;
        c.criteriaId = criteriaId;
        vm.prank(manager);
        listId = registry.createList(c, "");
    }

    function _input() internal pure returns (EntryInput memory i) {
        i.reason = "TEST";
    }

    function _add(bytes32 listId, SubjectRef memory s) internal returns (bytes32) {
        vm.prank(manager);
        return registry.addEntry(listId, s, _input(), "");
    }

    function _revoke(bytes32 listId, SubjectRef memory s) internal {
        vm.prank(manager);
        registry.revokeEntry(listId, _key(s), "TEST");
    }

    function _state(bytes32 listId) internal view returns (bytes32 state) {
        (, state) = registry.stateOf(listId);
    }

    function _match(bytes32 listId, SubjectRef memory s) internal view returns (Finding memory) {
        Request memory r;
        return registry.matchOf(listId, s, r, "");
    }

    function _match(bytes32 listId, SubjectRef memory s, bytes memory evidence) internal view returns (Finding memory) {
        Request memory r;
        return registry.matchOf(listId, s, r, evidence);
    }

    // ------------------------------------------------------------ bindings

    function _none() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function _one(bytes32 a) internal pure returns (bytes32[] memory l) {
        l = new bytes32[](1);
        l[0] = a;
    }

    function _two(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory l) {
        l = new bytes32[](2);
        l[0] = a;
        l[1] = b;
    }

    /// @dev A binding of the test venue: actor role, JOIN gated on every use, one list enough on
    /// each side, deny wins a conflict, no match is refused, the undetermined is deferred.
    function _config(bytes32[] memory allow, bytes32[] memory deny) internal view returns (BindingConfig memory c) {
        c.scope = Scope(address(venue), CONTEXT, keccak256("scope document"));
        c.role = Role.ACTOR;
        c.actions = new ActionRule[](1);
        c.actions[0] = ActionRule(JOIN, false);
        c.allow = new ListRef[](allow.length);
        for (uint256 i; i < allow.length; ++i) c.allow[i] = ListRef(address(registry), allow[i], bytes32(0));
        c.deny = new ListRef[](deny.length);
        for (uint256 i; i < deny.length; ++i) c.deny[i] = ListRef(address(registry), deny[i], bytes32(0));
        c.allowThreshold = allow.length == 0 ? 0 : 1;
        c.denyThreshold = deny.length == 0 ? 0 : 1;
        c.onConflict = Outcome.DENY;
        c.onNoMatch = Outcome.DENY;
        c.onIndeterminate = Disposition.DEFER;
        c.onNotApplicable = Disposition.PROCEED;
    }

    function _adopt(BindingConfig memory c) internal returns (bytes32 bindingId) {
        vm.prank(adopter);
        bindingId = guard.adopt(c, bytes32(++_salt), "");
    }

    function _assess(bytes32 bindingId, SubjectRef memory s, address presenter) internal view returns (Assessment memory) {
        return guard.assess(bindingId, s, presenter, JOIN, CONTEXT, new bytes[](0));
    }

    function _assess(bytes32 bindingId, SubjectRef memory s, address presenter, bytes[] memory evidence)
        internal
        view
        returns (Assessment memory)
    {
        return guard.assess(bindingId, s, presenter, JOIN, CONTEXT, evidence);
    }

    function _act(bytes32 bindingId, bytes32 action, SubjectRef memory s, address presenter)
        internal
        returns (Disposition d, Outcome o, bytes32 reason)
    {
        vm.prank(presenter);
        return venue.act(bindingId, action, CONTEXT, s, new bytes[](0));
    }

    function _evidence(bytes memory first) internal pure returns (bytes[] memory e) {
        e = new bytes[](1);
        e[0] = first;
    }

    function _evidence(bytes memory first, bytes memory second) internal pure returns (bytes[] memory e) {
        e = new bytes[](2);
        e[0] = first;
        e[1] = second;
    }

    // ------------------------------------------------------------ assertions

    function assertEq(Match a, Match b) internal pure {
        assertEq(uint8(a), uint8(b), "match");
    }

    function assertEq(Outcome a, Outcome b) internal pure {
        assertEq(uint8(a), uint8(b), "outcome");
    }

    function assertEq(Disposition a, Disposition b) internal pure {
        assertEq(uint8(a), uint8(b), "disposition");
    }

    function _expect(Finding memory f, Match result, bytes32 reason) internal pure {
        assertEq(uint8(f.result), uint8(result), "finding result");
        assertEq(f.reason, reason, "finding reason");
    }

    function _expect(Assessment memory a, Outcome outcome, bytes32 reason) internal pure {
        assertEq(uint8(a.outcome), uint8(outcome), "assessment outcome");
        assertEq(a.reason, reason, "assessment reason");
    }
}
