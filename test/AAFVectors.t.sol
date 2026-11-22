// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AAFBase.sol";
import {IAAFSubjectResolver} from "../assets/erc-8507/contracts/interfaces/IAAFSubjectResolver.sol";

/// @dev Replays the vectors written by tools/aaf.mjs, which computes them from the rules of the
/// specification without any of the Solidity code.
contract AAFVectorsTest is AAFBase {
    string internal constant DIR = "assets/erc-8507/vectors/";

    function _read(string memory name) internal view returns (string memory) {
        return vm.readFile(string.concat(DIR, name));
    }

    function _at(string memory array, uint256 i, string memory field) internal pure returns (string memory) {
        return string.concat(".", array, "[", vm.toString(i), "].", field);
    }

    // ------------------------------------------------------------ constants

    function test_vectors_tagsKindsAndEnums() public view {
        string memory j = _read("constants.json");
        assertEq(vm.parseJsonBytes32(j, ".tags.SCOPE_TAG"), SCOPE_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.CRITERIA_TAG"), CRITERIA_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.LIST_TAG"), LIST_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.STATE_TAG"), STATE_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.SET_LEAF_TAG"), SET_LEAF_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.BINDING_TAG"), BINDING_TAG);
        assertEq(vm.parseJsonBytes32(j, ".tags.DIGEST_TAG"), DIGEST_TAG);

        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.account']"), KIND_ACCOUNT);
        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.entry']"), KIND_ENTRY);
        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.group']"), KIND_GROUP);
        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.instance']"), KIND_INSTANCE);
        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.digest']"), KIND_DIGEST);
        assertEq(vm.parseJsonBytes32(j, ".subjectKinds['aaf.subject.name']"), KIND_NAME);
        assertEq(vm.parseJsonBytes32(j, ".actions['aaf.action.bid']"), BID);
        assertEq(vm.parseJsonBytes32(j, ".actions['aaf.action.join']"), JOIN);
        assertEq(vm.parseJsonBytes32(j, ".actions['aaf.action.invoke']"), INVOKE);

        assertEq(vm.parseJsonUint(j, ".enums.polarity.ALLOW"), uint8(Polarity.ALLOW));
        assertEq(vm.parseJsonUint(j, ".enums.polarity.DENY"), uint8(Polarity.DENY));
        assertEq(vm.parseJsonUint(j, ".enums.mode.ENUMERATED"), uint8(Mode.ENUMERATED));
        assertEq(vm.parseJsonUint(j, ".enums.mode.COMMITTED"), uint8(Mode.COMMITTED));
        assertEq(vm.parseJsonUint(j, ".enums.mode.PREDICATE"), uint8(Mode.PREDICATE));
        assertEq(vm.parseJsonUint(j, ".enums.mode.DERIVED"), uint8(Mode.DERIVED));
        assertEq(vm.parseJsonUint(j, ".enums.match.UNDETERMINED"), uint8(Match.UNDETERMINED));
        assertEq(vm.parseJsonUint(j, ".enums.match.MATCH"), uint8(Match.MATCH));
        assertEq(vm.parseJsonUint(j, ".enums.match.NO_MATCH"), uint8(Match.NO_MATCH));
        assertEq(vm.parseJsonUint(j, ".enums.outcome.INDETERMINATE"), uint8(Outcome.INDETERMINATE));
        assertEq(vm.parseJsonUint(j, ".enums.outcome.ALLOW"), uint8(Outcome.ALLOW));
        assertEq(vm.parseJsonUint(j, ".enums.outcome.DENY"), uint8(Outcome.DENY));
        assertEq(vm.parseJsonUint(j, ".enums.outcome.NOT_APPLICABLE"), uint8(Outcome.NOT_APPLICABLE));
        assertEq(vm.parseJsonUint(j, ".enums.disposition.REFUSE"), uint8(Disposition.REFUSE));
        assertEq(vm.parseJsonUint(j, ".enums.disposition.PROCEED"), uint8(Disposition.PROCEED));
        assertEq(vm.parseJsonUint(j, ".enums.disposition.DEFER"), uint8(Disposition.DEFER));
        assertEq(vm.parseJsonUint(j, ".enums.disposition.PROCEED_RESTRICTED"), uint8(Disposition.PROCEED_RESTRICTED));
        assertEq(vm.parseJsonUint(j, ".enums.setKind.MEMBERSHIP"), uint8(SetKind.MEMBERSHIP));
        assertEq(vm.parseJsonUint(j, ".enums.setKind.SORTED"), uint8(SetKind.SORTED));
        assertEq(vm.parseJsonUint(j, ".enums.role.ACTOR"), uint8(Role.ACTOR));
        assertEq(vm.parseJsonUint(j, ".enums.role.OBJECT"), uint8(Role.OBJECT));
        assertEq(vm.parseJsonUint(j, ".enums.reuse.NONE"), uint8(Reuse.NONE));
        assertEq(vm.parseJsonUint(j, ".enums.reuse.WHILE_CURRENT"), uint8(Reuse.WHILE_CURRENT));
        assertEq(vm.parseJsonUint(j, ".enums.reuse.ADMISSION"), uint8(Reuse.ADMISSION));
        // What an entry is tied to when it admits an account that has no code.
        assertEq(vm.parseJsonBytes32(j, ".emptyCodeHash"), keccak256(""));
    }

    function test_vectors_reasonCodes() public view {
        string memory j = _read("constants.json");
        bytes32[40] memory codes = [
            R_LISTED, R_NOT_LISTED, R_ENTRY_PENDING, R_ENTRY_EXPIRED, R_ENTRY_SUSPENDED, R_ENTRY_REVOKED,
            R_CONTROLLER_UNKNOWN, R_CONTROLLER_CHANGED, R_CODE_CHANGED, R_LIST_UNKNOWN, R_LIST_CLOSED, R_SET_MEMBER,
            R_SET_NON_MEMBER,
            R_SET_MISSING, R_PROOF_MISSING, R_PROOF_INVALID, R_NEGATIVE_UNSUPPORTED, R_MODULE_CHANGED, R_MODULE_FAILED,
            R_SOURCE_STATE_CHANGED, R_EXTENSION_LIMIT, R_RELATED, R_NOT_RELATED, R_RELATION_INCOMPLETE,
            R_ALLOW_MATCH, R_DENY_MATCH, R_CONFLICT, R_DEFAULT, R_UNDETERMINED_INPUT, R_BINDING_UNKNOWN, R_BINDING_RETIRED,
            R_CONSUMER_MISMATCH, R_ACTION_NOT_COVERED, R_CONTEXT_NOT_COVERED, R_LIST_STATE_CHANGED, R_REGISTRY_UNAVAILABLE,
            R_POLARITY_MISMATCH, R_PRESENTER_NOT_AUTHORIZED, R_STANDING_UNVERIFIED, R_ADMISSION_HONOURED
        ];
        string[] memory names = vm.parseJsonKeys(j, ".reasons");
        assertEq(names.length, codes.length);
        for (uint256 i; i < codes.length; ++i) {
            // A code is its name in ASCII, left-aligned.
            assertEq(vm.parseJsonBytes32(j, string.concat(".reasons.", names[i])), codes[i]);
            assertEq(bytes32(bytes(names[i])), codes[i]);
        }
    }

    function test_vectors_interfaceIdentifiers() public view {
        string memory j = _read("interfaces.json");
        assertEq(bytes4(vm.parseJsonBytes(j, ".IAAFRegistry.interfaceId")), type(IAAFRegistry).interfaceId);
        assertEq(bytes4(vm.parseJsonBytes(j, ".IAAFGuard.interfaceId")), type(IAAFGuard).interfaceId);
        assertEq(bytes4(vm.parseJsonBytes(j, ".IAAFEvaluator.interfaceId")), type(IAAFEvaluator).interfaceId);
        assertEq(bytes4(vm.parseJsonBytes(j, ".IAAFRelationSource.interfaceId")), type(IAAFRelationSource).interfaceId);
        assertEq(bytes4(vm.parseJsonBytes(j, ".IAAFSubjectResolver.interfaceId")), type(IAAFSubjectResolver).interfaceId);
        assertTrue(registry.supportsInterface(bytes4(vm.parseJsonBytes(j, ".IAAFRegistry.interfaceId"))));
        assertTrue(guard.supportsInterface(bytes4(vm.parseJsonBytes(j, ".IAAFGuard.interfaceId"))));
    }

    // ------------------------------------------------------------ identifiers

    function _world() internal returns (string memory j, AAFRegistry r, AAFGuard g) {
        j = _read("identifiers.json");
        vm.chainId(vm.parseJsonUint(j, ".chainId"));
        address registryAt = vm.parseJsonAddress(j, ".registry");
        address guardAt = vm.parseJsonAddress(j, ".guard");
        deployCodeTo("AAFRegistry.sol:AAFRegistry", registryAt);
        deployCodeTo("AAFGuard.sol:AAFGuard", guardAt);
        return (j, AAFRegistry(registryAt), AAFGuard(guardAt));
    }

    function test_vectors_subjectsScopesCriteria() public {
        (string memory j, AAFRegistry r,) = _world();

        bytes32[] memory keys = vm.parseJsonBytes32Array(j, ".subjectKeys");
        assertEq(keys.length, 9);
        for (uint256 i; i < keys.length; ++i) {
            SubjectRef memory s = SubjectRef({
                kind: keccak256(bytes(vm.parseJsonString(j, _at("subjects", i, "ref.kind")))),
                chainId: vm.parseJsonUint(j, _at("subjects", i, "ref.chainId")),
                namespace: vm.parseJsonAddress(j, _at("subjects", i, "ref.namespace")),
                id: vm.parseJsonBytes32(j, _at("subjects", i, "ref.id"))
            });
            assertEq(r.subjectKeyOf(s), keys[i]);
        }

        bytes32[] memory scopeIds = vm.parseJsonBytes32Array(j, ".scopeIds");
        assertEq(scopeIds.length, 3);
        for (uint256 i; i < scopeIds.length; ++i) {
            Scope memory scope = Scope({
                anchor: vm.parseJsonAddress(j, _at("scopes", i, "scope.anchor")),
                context: vm.parseJsonBytes32(j, _at("scopes", i, "scope.context")),
                documentHash: vm.parseJsonBytes32(j, _at("scopes", i, "scope.documentHash"))
            });
            assertEq(r.scopeIdOf(scope), scopeIds[i]);
            assertEq(r.declareScope(scope, ""), scopeIds[i]);
        }

        bytes32[] memory criteriaIds = vm.parseJsonBytes32Array(j, ".criteriaIds");
        assertEq(criteriaIds.length, 2);
        for (uint256 i; i < criteriaIds.length; ++i) {
            Criteria memory c = Criteria({
                documentHash: vm.parseJsonBytes32(j, _at("criteria", i, "criteria.documentHash")),
                module: vm.parseJsonAddress(j, _at("criteria", i, "criteria.module")),
                moduleCodeHash: vm.parseJsonBytes32(j, _at("criteria", i, "criteria.moduleCodeHash")),
                moduleConfig: vm.parseJsonBytes32(j, _at("criteria", i, "criteria.moduleConfig")),
                rule: vm.parseJsonBytes32(j, _at("criteria", i, "criteria.rule")),
                fanout: uint8(vm.parseJsonUint(j, _at("criteria", i, "criteria.fanout")))
            });
            assertEq(r.criteriaIdOf(c), criteriaIds[i]);
        }
    }

    function _listConfigAt(string memory j, uint256 i) internal pure returns (ListConfig memory c) {
        c.polarity = Polarity(uint8(vm.parseJsonUint(j, _at("lists", i, "config.polarity"))));
        c.mode = Mode(uint8(vm.parseJsonUint(j, _at("lists", i, "config.mode"))));
        c.scopeId = vm.parseJsonBytes32(j, _at("lists", i, "config.scopeId"));
        c.criteriaId = vm.parseJsonBytes32(j, _at("lists", i, "config.criteriaId"));
        c.noticePeriod = uint32(vm.parseJsonUint(j, _at("lists", i, "config.noticePeriod")));
        c.source = vm.parseJsonBytes32(j, _at("lists", i, "config.source"));
        c.sourcePin = vm.parseJsonBytes32(j, _at("lists", i, "config.sourcePin"));
        c.salt = vm.parseJsonBytes32(j, _at("lists", i, "config.salt"));
    }

    function test_vectors_listsBindingsDigests() public {
        (string memory j, AAFRegistry r, AAFGuard g) = _world();

        bytes32[] memory listIds = vm.parseJsonBytes32Array(j, ".listIds");
        assertEq(listIds.length, 7);
        uint256 created;
        for (uint256 i; i < listIds.length; ++i) {
            ListConfig memory c = _listConfigAt(j, i);
            address creator = vm.parseJsonAddress(j, _at("lists", i, "creator"));
            assertEq(r.listIdOf(creator, c), listIds[i]);
            // Lists without criteria can be created here; their first state is part of the vectors.
            if (c.criteriaId == bytes32(0)) {
                vm.prank(creator);
                assertEq(r.createList(c, ""), listIds[i]);
                (uint64 revision, bytes32 state) = r.stateOf(listIds[i]);
                assertEq(revision, vm.parseJsonUint(j, _at("lists", i, "revision")));
                assertEq(state, vm.parseJsonBytes32(j, _at("lists", i, "stateHash")));
                ++created;
            }
        }
        assertEq(created, 5);

        bytes32[] memory bindingIds = vm.parseJsonBytes32Array(j, ".bindingIds");
        assertEq(bindingIds.length, 5);
        for (uint256 i; i < bindingIds.length; ++i) {
            address consumer = vm.parseJsonAddress(j, _at("bindings", i, "consumer"));
            bytes32 scopeId = vm.parseJsonBytes32(j, _at("bindings", i, "scopeId"));
            bytes32 salt = vm.parseJsonBytes32(j, _at("bindings", i, "salt"));
            assertEq(g.bindingIdOf(consumer, scopeId, salt), bindingIds[i]);
            BindingConfig memory c = abi.decode(vm.parseJsonBytes(j, _at("bindings", i, "encoded")), (BindingConfig));
            assertEq(c.scope.anchor, consumer);
            assertEq(r.scopeIdOf(c.scope), scopeId);
            assertEq(keccak256(abi.encode(c)), vm.parseJsonBytes32(j, _at("bindings", i, "configHash")));
        }

        // The two bindings of Case C rest on lists that exist here: adopt them and read them back.
        for (uint256 i = 3; i < 5; ++i) {
            BindingConfig memory c = abi.decode(vm.parseJsonBytes(j, _at("bindings", i, "encoded")), (BindingConfig));
            vm.prank(c.scope.anchor);
            assertEq(g.adopt(c, vm.parseJsonBytes32(j, _at("bindings", i, "salt")), ""), bindingIds[i]);
            (BindingInfo memory info,) = g.bindingOf(bindingIds[i]);
            assertEq(info.configHash, vm.parseJsonBytes32(j, _at("bindings", i, "configHash")));
        }
        assertEq(g.stateDigestOf(bindingIds[3]), vm.parseJsonBytes32(j, ".digests[0].digest"));
    }

    // ------------------------------------------------------------ committed sets

    function test_vectors_setProofs() public view {
        string memory j = _read("sets.json");
        uint256 n = vm.parseJsonUint(j, ".count");
        assertEq(n, 7);
        for (uint256 i; i < n; ++i) {
            (Match m, bytes32 reason) = registry.verifySetProof(
                vm.parseJsonBytes32(j, _at("cases", i, "root")),
                SetKind(uint8(vm.parseJsonUint(j, _at("cases", i, "kind")))),
                uint64(vm.parseJsonUint(j, _at("cases", i, "size"))),
                vm.parseJsonBytes32(j, _at("cases", i, "key")),
                vm.parseJsonBytes(j, _at("cases", i, "evidence"))
            );
            assertEq(uint8(m), vm.parseJsonUint(j, _at("cases", i, "expect")), vm.parseJsonString(j, _at("cases", i, "label")));
            assertEq(reason, vm.parseJsonBytes32(j, _at("cases", i, "reason")));
        }
        // The tree of the vectors is the tree the test helper builds.
        bytes32[] memory keys = vm.parseJsonBytes32Array(j, ".sortedKeys");
        assertEq(SetTree.root(SetTree.build(keys)), vm.parseJsonBytes32(j, ".sortedRoot"));
    }

    // ------------------------------------------------------------ outcome rules

    function test_vectors_outcomeTable() public {
        string memory j = _read("outcomes.json");
        uint256[] memory allowSide = vm.parseJsonUintArray(j, ".allowSide");
        uint256[] memory denySide = vm.parseJsonUintArray(j, ".denySide");
        uint256[] memory onConflict = vm.parseJsonUintArray(j, ".onConflict");
        uint256[] memory onNoMatch = vm.parseJsonUintArray(j, ".onNoMatch");
        uint256[] memory outcome = vm.parseJsonUintArray(j, ".outcome");
        assertEq(outcome.length, 81);

        ScriptedEvaluator a = new ScriptedEvaluator();
        ScriptedEvaluator d = new ScriptedEvaluator();
        bytes32 allowList = _predicateList(Polarity.ALLOW, address(a));
        bytes32 denyList = _predicateList(Polarity.DENY, address(d));
        bytes32 binding;
        for (uint256 i; i < outcome.length; ++i) {
            if (i % 9 == 0) {
                BindingConfig memory c = _config(_one(allowList), _one(denyList));
                c.onConflict = Outcome(uint8(onConflict[i]));
                c.onNoMatch = Outcome(uint8(onNoMatch[i]));
                binding = _adopt(c);
            }
            a.set(Match(uint8(allowSide[i])));
            d.set(Match(uint8(denySide[i])));
            assertEq(uint8(_assess(binding, _account(alice), alice).outcome), outcome[i]);
        }
    }

    function test_vectors_thresholds() public {
        string memory j = _read("outcomes.json");
        uint256[] memory first = vm.parseJsonUintArray(j, ".thresholds.first");
        uint256[] memory second = vm.parseJsonUintArray(j, ".thresholds.second");
        uint256[] memory third = vm.parseJsonUintArray(j, ".thresholds.third");
        uint256[] memory threshold = vm.parseJsonUintArray(j, ".thresholds.threshold");
        uint256[] memory expected = vm.parseJsonUintArray(j, ".thresholds.side");
        assertEq(expected.length, 81);

        ScriptedEvaluator[3] memory e = [new ScriptedEvaluator(), new ScriptedEvaluator(), new ScriptedEvaluator()];
        bytes32[] memory lists = new bytes32[](3);
        for (uint256 i; i < 3; ++i) lists[i] = _predicateList(Polarity.ALLOW, address(e[i]));
        bytes32[4] memory bindings;
        for (uint8 t = 1; t <= 3; ++t) {
            BindingConfig memory c = _config(lists, _none());
            c.allowThreshold = t;
            bindings[t] = _adopt(c);
        }
        for (uint256 i; i < expected.length; ++i) {
            e[0].set(Match(uint8(first[i])));
            e[1].set(Match(uint8(second[i])));
            e[2].set(Match(uint8(third[i])));
            assertEq(uint8(_assess(bindings[threshold[i]], _account(alice), alice).allowSide), expected[i]);
        }
    }
}
