// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AAFBase.sol";
import {AAFBoundAnchorRelation} from "../assets/erc-8507/contracts/adapters/AAFBoundAnchorRelation.sol";
import {AIDRegistry} from "./vendor/aid/AIDRegistry.sol";

contract AAFDerivedTest is AAFBase {
    ScriptedRelation internal relation;
    bytes32 internal source;
    bytes32 internal relationCriteria;

    function setUp() public override {
        super.setUp();
        relation = new ScriptedRelation();
        source = _list(Polarity.DENY);
        relationCriteria =
            registry.registerCriteria(keccak256("extension"), address(relation), relation.RELATION(), 2, "");
    }

    // ------------------------------------------------------------ reference

    function test_reference_followsItsSource() public {
        bytes32 derived = _derivedList(source, bytes32(0), bytes32(0));
        SubjectRef memory s = _account(alice);
        _expect(_match(derived, s), Match.NO_MATCH, R_NOT_LISTED);
        bytes32 before = _state(derived);
        _add(source, s);
        _expect(_match(derived, s), Match.MATCH, R_LISTED);
        assertTrue(_state(derived) != before); // the state of a derived list covers its source
        _revoke(source, s);
        _expect(_match(derived, s), Match.NO_MATCH, R_ENTRY_REVOKED);
    }

    function test_reference_pinnedToAState_stopsWhenTheSourceMoves() public {
        _add(source, _account(alice));
        bytes32 derived = _derivedList(source, bytes32(0), _state(source));
        _expect(_match(derived, _account(alice)), Match.MATCH, R_LISTED);

        _add(source, _account(bob));
        // The subscriber agreed to the list as it was. Until it agrees to the new state it says nothing,
        // also about subjects whose own entries did not change.
        _expect(_match(derived, _account(bob)), Match.UNDETERMINED, R_SOURCE_STATE_CHANGED);
        _expect(_match(derived, _account(alice)), Match.UNDETERMINED, R_SOURCE_STATE_CHANGED);

        bytes32 pin = _state(source);
        vm.expectEmit();
        emit IAAFRegistry.SourcePinSet(derived, pin);
        vm.prank(manager);
        registry.setSourcePin(derived, pin);
        _expect(_match(derived, _account(bob)), Match.MATCH, R_LISTED);
    }

    function test_reference_keepsThePolarityOfItsSource() public {
        ListConfig memory c = _listConfig(Polarity.ALLOW, Mode.DERIVED);
        c.source = source; // a deny list
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");
        c.source = keccak256("no such list");
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.UnknownList.selector);
        registry.createList(c, "");
    }

    function test_reference_chainsAreBoundedAndCannotLoop() public {
        // A list names its source when it is created and the source must exist: no cycle can be built.
        bytes32 current = source;
        for (uint256 i; i < registry.MAX_DEPTH(); ++i) {
            current = _derivedList(current, bytes32(0), bytes32(0));
            assertEq(registry.listOf(current).depth, i + 1);
        }
        _add(source, _account(alice));
        _expect(_match(current, _account(alice)), Match.MATCH, R_LISTED);

        ListConfig memory c = _listConfig(Polarity.DENY, Mode.DERIVED);
        c.source = current;
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");
    }

    function test_reference_ofAClosedSource_isUndetermined() public {
        bytes32 derived = _derivedList(source, bytes32(0), bytes32(0));
        vm.prank(manager);
        registry.closeList(source);
        // A dependency that cannot answer is not skipped.
        _expect(_match(derived, _account(alice)), Match.UNDETERMINED, R_LIST_CLOSED);
    }

    // ------------------------------------------------------------ related-object extension

    function test_extension_reachesObjectsRelatedToAListedOne() public {
        bytes32 extended = _derivedList(source, relationCriteria, bytes32(0));
        SubjectRef memory listed = _account(alice);
        SubjectRef memory related = _account(bob);
        relation.relate(listed, related);

        _expect(_match(extended, related), Match.NO_MATCH, R_NOT_RELATED); // the origin is not listed
        _add(source, listed);
        Finding memory f = _match(extended, related);
        _expect(f, Match.MATCH, R_RELATED);
        assertEq(f.derivedFrom, _key(listed)); // the ground of the derived match is kept
        assertEq(f.validUntil, 0); // read now; it holds for this call

        // The source list itself is not extended. Extension exists only where a list declares it.
        _expect(_match(source, related), Match.NO_MATCH, R_NOT_LISTED);
        // The listed object is not a member of the extension unless it is related to a listed one.
        _expect(_match(extended, listed), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_extension_isRecomputed() public {
        bytes32 extended = _derivedList(source, relationCriteria, bytes32(0));
        relation.relate(_account(alice), _account(bob));
        _add(source, _account(alice));
        _expect(_match(extended, _account(bob)), Match.MATCH, R_RELATED);
        _revoke(source, _account(alice));
        _expect(_match(extended, _account(bob)), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_extension_sourceThatCannotTell_isUndetermined() public {
        bytes32 extended = _derivedList(source, relationCriteria, bytes32(0));
        relation.setOpen(_account(bob), true); // the source cannot say that it named every origin
        _expect(_match(extended, _account(bob)), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
        relation.setOpen(_account(bob), false);
        relation.setBroken(true);
        _expect(_match(extended, _account(bob)), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
    }

    function test_extension_fanOutIsBounded() public {
        bytes32 extended = _derivedList(source, relationCriteria, bytes32(0)); // at most two origins
        relation.relate(_account(alice), _account(bob));
        relation.relate(_account(carol), _account(bob));
        relation.relate(_account(mallory), _account(bob));
        _add(source, _account(mallory)); // the third origin is the listed one
        // Two origins were looked at and more exist: not a match, and not a confirmed absence either.
        _expect(_match(extended, _account(bob)), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
        _add(source, _account(carol));
        _expect(_match(extended, _account(bob)), Match.MATCH, R_RELATED);
    }

    function test_extension_isNotTransitive() public {
        bytes32 extended = _derivedList(source, relationCriteria, bytes32(0));
        bytes32 twice = _derivedList(extended, relationCriteria, bytes32(0));
        relation.relate(_account(alice), _account(bob));
        relation.relate(_account(bob), _account(carol));
        _add(source, _account(alice));
        _expect(_match(extended, _account(bob)), Match.MATCH, R_RELATED);
        // carol is related to bob, who is only related to a listed object: one hop is the limit.
        _expect(_match(twice, _account(carol)), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
        // A plain reference to an extension adds no hop.
        bytes32 mirror = _derivedList(extended, bytes32(0), bytes32(0));
        _expect(_match(mirror, _account(bob)), Match.MATCH, R_RELATED);
    }

    function test_extension_unknownRelationType_isUndetermined() public {
        bytes32 other = registry.registerCriteria(keccak256("extension"), address(relation), keccak256("other"), 2, "");
        bytes32 extended = _derivedList(source, other, bytes32(0));
        _expect(_match(extended, _account(bob)), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
    }

    function test_extension_criteriaMustDeclareFanOut() public {
        bytes32 noFanOut = registry.registerCriteria(keccak256("extension"), address(relation), relation.RELATION(), 0, "");
        ListConfig memory c = _listConfig(Polarity.DENY, Mode.DERIVED);
        c.source = source;
        c.criteriaId = noFanOut;
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");
    }
}

/// @dev The extension run against the address-anchored identity registry.
contract AAFBoundAnchorTest is AAFBase {
    AIDRegistry internal anchors;
    AAFBoundAnchorRelation internal relation;
    bytes32 internal denied; // lists agent identities
    bytes32 internal extended; // their bound anchors
    uint256 internal agentId;
    SubjectRef internal agent;

    address internal anchorA = makeAddr("anchor A");
    address internal anchorB = makeAddr("anchor B");

    function setUp() public override {
        super.setUp();
        anchors = new AIDRegistry(90 days, 365 days);
        relation = new AAFBoundAnchorRelation(address(anchors));
        denied = _list(Polarity.DENY);
        extended = _derivedList(
            denied,
            registry.registerCriteria(keccak256("extension"), address(relation), relation.RELATION_BOUND_ANCHOR(), 1, ""),
            bytes32(0)
        );

        vm.startPrank(anchorA);
        agentId = identities.register();
        anchors.bind(address(identities), agentId);
        vm.stopPrank();
        agent = _entry(address(identities), agentId);
        _add(denied, agent);
    }

    function test_boundAnchor_isReachedOnlyThroughTheExtension() public view {
        SubjectRef memory a = _account(anchorA);
        // The list names the identity. The account behind it is another object.
        _expect(_match(denied, a), Match.NO_MATCH, R_NOT_LISTED);
        Finding memory f = _match(extended, a);
        _expect(f, Match.MATCH, R_RELATED);
        assertEq(f.derivedFrom, _key(agent));
        // An account with no binding is confirmed unrelated: the enumeration is complete.
        _expect(_match(extended, _account(bob)), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_namingASuccessor_extendsNothing() public {
        // The listed side retires and names an uninvolved account as its successor.
        vm.prank(anchorA);
        anchors.retire(carol);
        assertEq(anchors.successorOf(anchorA), carol);
        // carol did nothing. A statement by the listed side alone does not reach her.
        _expect(_match(extended, _account(carol)), Match.NO_MATCH, R_NOT_RELATED);
        _expect(_match(denied, _account(carol)), Match.NO_MATCH, R_NOT_LISTED);
    }

    function test_takingOverTheIdentity_isWhatRelates() public {
        // The identity changes hands and the new holder binds itself to it.
        vm.prank(anchorA);
        identities.transferFrom(anchorA, anchorB, agentId);
        _expect(_match(extended, _account(anchorB)), Match.NO_MATCH, R_NOT_RELATED); // not bound yet
        vm.prank(anchorB);
        anchors.bind(address(identities), agentId);
        Finding memory f = _match(extended, _account(anchorB));
        _expect(f, Match.MATCH, R_RELATED);
        assertEq(f.derivedFrom, _key(agent));
        // The former anchor no longer satisfies the relation.
        _expect(_match(extended, _account(anchorA)), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_derivedResult_followsTheOriginAndTheRelation() public {
        _expect(_match(extended, _account(anchorA)), Match.MATCH, R_RELATED);
        // The identity leaves the list: the derived match goes with it.
        _revoke(denied, agent);
        _expect(_match(extended, _account(anchorA)), Match.NO_MATCH, R_NOT_RELATED);
        _add(denied, agent);
        _expect(_match(extended, _account(anchorA)), Match.MATCH, R_RELATED);
        // The relation ends: so does the derived match.
        vm.prank(anchorA);
        anchors.unbind();
        _expect(_match(extended, _account(anchorA)), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_bindingTheIdentityNoLongerNames_isNoRelation() public {
        // The binding record remains, but the identity now names somebody else.
        vm.prank(anchorA);
        identities.transferFrom(anchorA, anchorB, agentId);
        assertEq(anchors.bindingOf(anchorA).agentId, agentId);
        _expect(_match(extended, _account(anchorA)), Match.NO_MATCH, R_NOT_RELATED);
    }

    function test_agentWallet_countsAsNamed() public {
        address wallet = makeAddr("wallet");
        vm.prank(anchorA);
        identities.setAgentWallet(agentId, wallet);
        vm.prank(anchorA);
        anchors.unbind();
        vm.prank(wallet);
        anchors.bind(address(identities), agentId);
        _expect(_match(extended, _account(wallet)), Match.MATCH, R_RELATED);
    }

    function test_otherKindsAndChains() public view {
        // A registry entry cannot be a bound anchor: confirmed unrelated.
        _expect(_match(extended, agent), Match.NO_MATCH, R_NOT_RELATED);
        // An account on another chain cannot be read from here.
        SubjectRef memory elsewhere = SubjectRef(KIND_ACCOUNT, block.chainid + 1, address(0), bytes32(uint256(uint160(anchorA))));
        _expect(_match(extended, elsewhere), Match.UNDETERMINED, R_RELATION_INCOMPLETE);
    }
}
