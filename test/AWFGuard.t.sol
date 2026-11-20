// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AWFBase.sol";
import {IERC165} from "../assets/erc-9999/contracts/Introspection.sol";
import {IAWFSubjectResolver} from "../assets/erc-9999/contracts/interfaces/IAWFSubjectResolver.sol";

contract ScriptedResolver is IAWFSubjectResolver {
    Match public answer;
    address public controller;
    bool public broken;

    function set(Match answer_, address controller_) external {
        answer = answer_;
        controller = controller_;
    }

    function setBroken(bool broken_) external {
        broken = broken_;
    }

    function standingOf(SubjectRef calldata, address) external view returns (Match, address) {
        require(!broken, "broken");
        return (answer, controller);
    }
}

contract AWFGuardTest is AWFBase {
    bytes32 internal constant ACCESS = keccak256("awf.action.access");

    ScriptedEvaluator internal allowEvaluator;
    ScriptedEvaluator internal denyEvaluator;
    bytes32 internal allowList;
    bytes32 internal denyList;

    function setUp() public override {
        super.setUp();
        allowEvaluator = new ScriptedEvaluator();
        denyEvaluator = new ScriptedEvaluator();
        allowList = _predicateList(Polarity.ALLOW, address(allowEvaluator));
        denyList = _predicateList(Polarity.DENY, address(denyEvaluator));
    }

    // ------------------------------------------------------------ adoption

    function test_adopt_storesWhatWasDeclared() public {
        BindingConfig memory c = _config(_one(allowList), _one(denyList));
        c.documentHash = keccak256("binding document");
        bytes32 scopeId = registry.scopeIdOf(c.scope);
        bytes32 expected = guard.bindingIdOf(address(venue), scopeId, bytes32(uint256(77)));
        assertEq(
            expected, keccak256(abi.encode(BINDING_TAG, block.chainid, address(guard), address(venue), scopeId, bytes32(uint256(77))))
        );

        vm.expectEmit();
        emit IAWFGuard.BindingAdopted(expected, address(venue), scopeId, keccak256(abi.encode(c)), adopter, "ipfs://binding");
        vm.prank(adopter);
        bytes32 id = guard.adopt(c, bytes32(uint256(77)), "ipfs://binding");
        assertEq(id, expected);

        (BindingInfo memory info, BindingConfig memory stored) = guard.bindingOf(id);
        assertEq(info.consumer, address(venue));
        assertEq(info.adoptedBy, adopter);
        assertEq(info.version, 1);
        assertEq(info.scopeId, scopeId);
        assertEq(info.configHash, keccak256(abi.encode(c)));
        assertEq(keccak256(abi.encode(stored)), keccak256(abi.encode(c)));

        vm.prank(adopter);
        vm.expectRevert(IAWFGuard.BindingExists.selector);
        guard.adopt(c, bytes32(uint256(77)), "");
    }

    function test_adopt_onlyTheConsumerOrItsAdopter() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        // Publishing a list, or wishing a consumer used it, binds nobody.
        vm.prank(manager);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.adopt(c, bytes32(0), "");
        // The consumer itself may adopt.
        vm.prank(address(venue));
        guard.adopt(c, bytes32(0), "");
        // An account is a consumer too, for instance an agent runtime gating its own actions.
        c.scope.anchor = alice;
        vm.prank(alice);
        guard.adopt(c, bytes32(0), "");
    }

    function test_setAdopter_movesTheAuthority() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        vm.expectEmit();
        emit IAWFGuard.AdopterSet(address(venue), bob);
        vm.prank(address(venue));
        guard.setAdopter(bob);
        assertEq(guard.adopterOf(address(venue)), bob);
        vm.prank(adopter);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.adopt(c, bytes32(0), "");
        vm.prank(bob);
        guard.adopt(c, bytes32(0), "");
    }

    function test_adopt_refusesIncompleteDeclarations() public {
        BindingConfig memory c = _config(_one(allowList), _one(denyList));
        c.actions = new ActionRule[](0);
        _refused(c);

        c = _config(_none(), _none()); // no list at all
        _refused(c);

        c = _config(_one(allowList), _one(denyList));
        c.allowThreshold = 0;
        _refused(c);
        c.allowThreshold = 2; // more than there are lists
        _refused(c);

        c = _config(_one(allowList), _none());
        c.denyThreshold = 1; // a threshold for an empty side
        _refused(c);

        c = _config(_one(allowList), _one(denyList));
        c.onConflict = Outcome.NOT_APPLICABLE;
        _refused(c);
        c = _config(_one(allowList), _one(denyList));
        c.onNoMatch = Outcome.INDETERMINATE;
        _refused(c);

        c = _config(_one(denyList), _none()); // a deny list on the allow side
        _refused(c);
        c = _config(_one(keccak256("no such list")), _none());
        _refused(c);
        c = _config(_one(allowList), _none());
        c.allow[0].registry = alice; // not a contract
        _refused(c);
    }

    function _refused(BindingConfig memory c) internal {
        vm.prank(adopter);
        vm.expectRevert(IAWFGuard.InvalidBinding.selector);
        guard.adopt(c, bytes32(uint256(1)), "");
    }

    function test_amend_raisesTheVersionAndKeepsTheScope() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.NO_MATCH);
        _expect(_assess(id, _account(alice), alice), Outcome.DENY, R_DEFAULT);
        bytes32 digest = guard.stateDigestOf(id);

        c.onNoMatch = Outcome.ALLOW;
        vm.expectEmit();
        emit IAWFGuard.BindingAmended(id, 2, keccak256(abi.encode(c)), adopter, "ipfs://v2");
        vm.prank(adopter);
        guard.amend(id, c, "ipfs://v2");
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.ALLOW, R_DEFAULT);
        assertEq(a.bindingVersion, 2);
        assertTrue(guard.stateDigestOf(id) != digest);

        vm.prank(mallory);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.amend(id, c, "");
        c.scope.context = keccak256("another context");
        vm.prank(adopter);
        vm.expectRevert(IAWFGuard.InvalidBinding.selector);
        guard.amend(id, c, "");
    }

    function test_retire_endsTheBinding() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        vm.prank(mallory);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.retire(id);
        vm.expectEmit();
        emit IAWFGuard.BindingRetired(id, adopter);
        vm.prank(adopter);
        guard.retire(id);
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.NOT_APPLICABLE, R_BINDING_RETIRED);
        assertFalse(guard.isCurrent(id, guard.stateDigestOf(id), type(uint64).max));
        vm.prank(adopter);
        vm.expectRevert(IAWFGuard.BindingIsRetired.selector);
        guard.amend(id, _config(_one(allowList), _none()), "");
    }

    function test_unknownBinding() public {
        Assessment memory a = _assess(keccak256("no such binding"), _account(alice), alice);
        _expect(a, Outcome.NOT_APPLICABLE, R_BINDING_UNKNOWN);
        assertEq(a.disposition, Disposition.REFUSE);
        vm.expectRevert(IAWFGuard.UnknownBinding.selector);
        guard.enforce(keccak256("no such binding"), _account(alice), alice, JOIN, CONTEXT, new bytes[](0));
    }

    function test_supportsInterface() public view {
        assertTrue(guard.supportsInterface(type(IAWFGuard).interfaceId));
        assertTrue(guard.supportsInterface(type(IERC165).interfaceId));
        assertFalse(guard.supportsInterface(0xffffffff));
    }

    // ------------------------------------------------------------ outcome rules

    /// @dev The table of the specification, written out case by case.
    function _expected(Match a, Match d, Outcome onConflict, Outcome onNoMatch) internal pure returns (Outcome) {
        if (a == Match.MATCH && d == Match.MATCH) return onConflict;
        if (a == Match.MATCH && d == Match.NO_MATCH) return Outcome.ALLOW;
        if (a == Match.NO_MATCH && d == Match.MATCH) return Outcome.DENY;
        if (a == Match.NO_MATCH && d == Match.NO_MATCH) return onNoMatch;
        if (a == Match.MATCH && d == Match.UNDETERMINED) {
            return onConflict == Outcome.ALLOW ? Outcome.ALLOW : Outcome.INDETERMINATE;
        }
        if (a == Match.UNDETERMINED && d == Match.MATCH) {
            return onConflict == Outcome.DENY ? Outcome.DENY : Outcome.INDETERMINATE;
        }
        if (a == Match.NO_MATCH && d == Match.UNDETERMINED) {
            return onNoMatch == Outcome.DENY ? Outcome.DENY : Outcome.INDETERMINATE;
        }
        if (a == Match.UNDETERMINED && d == Match.NO_MATCH) {
            return onNoMatch == Outcome.ALLOW ? Outcome.ALLOW : Outcome.INDETERMINATE;
        }
        return Outcome.INDETERMINATE;
    }

    function test_outcome_everyCombinationOfSidesAndRules() public {
        Outcome[3] memory conflictRules = [Outcome.ALLOW, Outcome.DENY, Outcome.INDETERMINATE];
        Outcome[3] memory defaultRules = [Outcome.ALLOW, Outcome.DENY, Outcome.NOT_APPLICABLE];
        SubjectRef memory s = _account(alice);
        uint256 checked;
        for (uint256 i; i < 3; ++i) {
            for (uint256 j; j < 3; ++j) {
                BindingConfig memory c = _config(_one(allowList), _one(denyList));
                c.onConflict = conflictRules[i];
                c.onNoMatch = defaultRules[j];
                bytes32 id = _adopt(c);
                for (uint8 a; a < 3; ++a) {
                    for (uint8 d; d < 3; ++d) {
                        allowEvaluator.set(Match(a));
                        denyEvaluator.set(Match(d));
                        Assessment memory r = _assess(id, s, alice);
                        assertEq(uint8(r.allowSide), a);
                        assertEq(uint8(r.denySide), d);
                        assertEq(r.outcome, _expected(Match(a), Match(d), c.onConflict, c.onNoMatch));
                        ++checked;
                    }
                }
            }
        }
        assertEq(checked, 81);
    }

    function test_outcome_reasons() public {
        bytes32 id = _adopt(_config(_one(allowList), _one(denyList)));
        SubjectRef memory s = _account(alice);
        allowEvaluator.set(Match.MATCH);
        denyEvaluator.set(Match.NO_MATCH);
        _expect(_assess(id, s, alice), Outcome.ALLOW, R_ALLOW_MATCH);
        denyEvaluator.set(Match.MATCH);
        _expect(_assess(id, s, alice), Outcome.DENY, R_CONFLICT);
        allowEvaluator.set(Match.NO_MATCH);
        _expect(_assess(id, s, alice), Outcome.DENY, R_DENY_MATCH);
        denyEvaluator.set(Match.NO_MATCH);
        _expect(_assess(id, s, alice), Outcome.DENY, R_DEFAULT);
        allowEvaluator.set(Match.MATCH);
        denyEvaluator.set(Match.UNDETERMINED);
        _expect(_assess(id, s, alice), Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
    }

    function test_unresolvedConflict_isIndeterminate() public {
        BindingConfig memory c = _config(_one(allowList), _one(denyList));
        c.onConflict = Outcome.INDETERMINATE;
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.MATCH);
        denyEvaluator.set(Match.MATCH);
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.INDETERMINATE, R_CONFLICT);
        assertEq(a.disposition, Disposition.DEFER);
    }

    function test_threshold_anyAndAllOverThreeValues() public {
        ScriptedEvaluator second = new ScriptedEvaluator();
        bytes32 secondList = _predicateList(Polarity.ALLOW, address(second));
        BindingConfig memory c = _config(_two(allowList, secondList), _none());
        bytes32 any = _adopt(c);
        c.allowThreshold = 2;
        bytes32 all = _adopt(c);
        SubjectRef memory s = _account(alice);

        // first list, second list, side under ANY, side under ALL
        uint8[4][6] memory rows = [
            [uint8(Match.MATCH), uint8(Match.MATCH), uint8(Match.MATCH), uint8(Match.MATCH)],
            [uint8(Match.MATCH), uint8(Match.NO_MATCH), uint8(Match.MATCH), uint8(Match.NO_MATCH)],
            [uint8(Match.MATCH), uint8(Match.UNDETERMINED), uint8(Match.MATCH), uint8(Match.UNDETERMINED)],
            [uint8(Match.NO_MATCH), uint8(Match.UNDETERMINED), uint8(Match.UNDETERMINED), uint8(Match.NO_MATCH)],
            [uint8(Match.NO_MATCH), uint8(Match.NO_MATCH), uint8(Match.NO_MATCH), uint8(Match.NO_MATCH)],
            [uint8(Match.UNDETERMINED), uint8(Match.UNDETERMINED), uint8(Match.UNDETERMINED), uint8(Match.UNDETERMINED)]
        ];
        for (uint256 i; i < rows.length; ++i) {
            allowEvaluator.set(Match(rows[i][0]));
            second.set(Match(rows[i][1]));
            assertEq(uint8(_assess(any, s, alice).allowSide), rows[i][2], "any");
            assertEq(uint8(_assess(all, s, alice).allowSide), rows[i][3], "all");
        }
    }

    // ------------------------------------------------------------ coverage

    function test_notApplicable_whenActionOrContextIsNotCovered() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        c.onNotApplicable = Disposition.REFUSE;
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.MATCH);

        Assessment memory a = guard.assess(id, _account(alice), alice, BID, CONTEXT, new bytes[](0));
        _expect(a, Outcome.NOT_APPLICABLE, R_ACTION_NOT_COVERED);
        assertEq(a.disposition, Disposition.REFUSE);
        assertEq(a.findings.length, 0); // no list was asked

        a = guard.assess(id, _account(alice), alice, JOIN, keccak256("context/2"), new bytes[](0));
        _expect(a, Outcome.NOT_APPLICABLE, R_CONTEXT_NOT_COVERED);
    }

    function test_scopeWithoutContext_coversEveryContextOfTheConsumer() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        c.scope.context = bytes32(0);
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.MATCH);
        Assessment memory a = guard.assess(id, _account(alice), alice, JOIN, keccak256("any context"), new bytes[](0));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
    }

    function test_defaultMayBeNotApplicable() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        c.onNoMatch = Outcome.NOT_APPLICABLE; // this binding only ever speaks for its members
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.NO_MATCH);
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.NOT_APPLICABLE, R_DEFAULT);
        assertEq(a.disposition, Disposition.PROCEED);
    }

    // ------------------------------------------------------------ standing

    function test_standing_anAccountActsForItself() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        allowEvaluator.set(Match.MATCH);
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.standing, Match.MATCH);
        assertEq(a.controller, alice);

        // Naming a listed subject is not the same as being entitled to act for it.
        a = _assess(id, _account(alice), mallory);
        _expect(a, Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        assertEq(a.allowSide, Match.MATCH); // the list result is unchanged; it is just not hers to use
    }

    function test_standing_withoutPresenter_nothingIsGranted() public {
        bytes32 id = _adopt(_config(_one(allowList), _one(denyList)));
        allowEvaluator.set(Match.MATCH);
        denyEvaluator.set(Match.NO_MATCH);
        _expect(_assess(id, _account(alice), address(0)), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
        // A refusal needs no presenter.
        denyEvaluator.set(Match.MATCH);
        _expect(_assess(id, _account(alice), address(0)), Outcome.DENY, R_CONFLICT);
    }

    function test_standing_registryEntry_ownerApprovedOperator() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        allowEvaluator.set(Match.MATCH);
        vm.prank(alice);
        uint256 agentId = identities.register();
        SubjectRef memory s = _entry(address(identities), agentId);

        Assessment memory a = _assess(id, s, alice);
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.controller, alice);
        _expect(_assess(id, s, bob), Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);

        vm.prank(alice);
        identities.approve(bob, agentId);
        a = _assess(id, s, bob);
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.controller, alice); // an approved account acts for the owner; it does not become the controller

        vm.prank(alice);
        identities.setApprovalForAll(carol, true);
        _expect(_assess(id, s, carol), Outcome.ALLOW, R_ALLOW_MATCH);

        // After a transfer the former owner and its single approval have no standing left.
        vm.prank(alice);
        identities.transferFrom(alice, mallory, agentId);
        _expect(_assess(id, s, alice), Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        _expect(_assess(id, s, bob), Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        assertEq(_assess(id, s, mallory).controller, mallory);
    }

    function test_standing_whatCannotBeReadIsUnverified() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        allowEvaluator.set(Match.MATCH);
        // an entry that does not exist
        _expect(_assess(id, _entry(address(identities), 999), alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
        // an account on another chain: referring to it does not verify it
        SubjectRef memory elsewhere = SubjectRef(KIND_ACCOUNT, block.chainid + 1, address(0), bytes32(uint256(uint160(alice))));
        _expect(_assess(id, elsewhere, alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
        // a kind the built-in rules do not cover
        SubjectRef memory group = SubjectRef(KIND_GROUP, block.chainid, address(identities), bytes32(uint256(1)));
        _expect(_assess(id, group, alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
        // a malformed account reference
        SubjectRef memory odd = SubjectRef(KIND_ACCOUNT, block.chainid, address(1), bytes32(uint256(uint160(alice))));
        _expect(_assess(id, odd, alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
    }

    function test_standing_resolverDecidesForOtherKinds() public {
        ScriptedResolver resolver = new ScriptedResolver();
        BindingConfig memory c = _config(_one(allowList), _none());
        c.resolver = address(resolver);
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.MATCH);
        SubjectRef memory group = SubjectRef(KIND_GROUP, block.chainid, address(identities), bytes32(uint256(1)));

        resolver.set(Match.MATCH, carol);
        Assessment memory a = _assess(id, group, alice);
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.controller, carol);
        resolver.set(Match.NO_MATCH, carol);
        _expect(_assess(id, group, alice), Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        resolver.set(Match.UNDETERMINED, address(0));
        _expect(_assess(id, group, alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
        resolver.setBroken(true);
        _expect(_assess(id, group, alice), Outcome.INDETERMINATE, R_STANDING_UNVERIFIED);
    }

    function test_controllerTiedEntry_followsTheControllerTheGuardEstablished() public {
        bytes32 members = _list(Polarity.ALLOW);
        vm.prank(alice);
        uint256 agentId = identities.register();
        SubjectRef memory s = _entry(address(identities), agentId);
        EntryInput memory input = _input();
        input.controller = alice; // admitted as controlled by alice
        vm.prank(manager);
        registry.addEntry(members, s, input, "");
        bytes32 id = _adopt(_config(_one(members), _none()));

        _expect(_assess(id, s, alice), Outcome.ALLOW, R_ALLOW_MATCH);
        vm.prank(alice);
        identities.transferFrom(alice, bob, agentId);
        // The new owner holds the identity, and the admission was not given to it.
        Assessment memory a = _assess(id, s, bob);
        _expect(a, Outcome.DENY, R_DEFAULT);
        _expect(a.findings[0], Match.NO_MATCH, R_CONTROLLER_CHANGED);
    }

    // ------------------------------------------------------------ objects

    function test_objectRole_needsNoStanding() public {
        bytes32 excluded = _list(Polarity.DENY);
        SubjectRef memory badTool = _artefact(keccak256("tool v1.2 package"));
        SubjectRef memory goodTool = _artefact(keccak256("tool v1.3 package"));
        _add(excluded, badTool);
        BindingConfig memory c = _config(_none(), _one(excluded));
        c.role = Role.OBJECT;
        c.onNoMatch = Outcome.ALLOW;
        c.actions[0] = ActionRule(INVOKE, false);
        bytes32 id = _adopt(c);

        Assessment memory a = guard.assess(id, badTool, alice, INVOKE, CONTEXT, new bytes[](0));
        _expect(a, Outcome.DENY, R_DENY_MATCH);
        a = guard.assess(id, goodTool, alice, INVOKE, CONTEXT, new bytes[](0));
        _expect(a, Outcome.ALLOW, R_DEFAULT);
        // Whoever calls, the question is about the tool.
        a = guard.assess(id, goodTool, address(0), INVOKE, CONTEXT, new bytes[](0));
        _expect(a, Outcome.ALLOW, R_DEFAULT);
    }

    // ------------------------------------------------------------ dispositions and records

    function test_disposition_followsTheDeclaredRules() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        bytes32 deferring = _adopt(c);
        c.onIndeterminate = Disposition.REFUSE;
        bytes32 refusing = _adopt(c);
        c.onIndeterminate = Disposition.PROCEED_RESTRICTED;
        bytes32 lenient = _adopt(c);
        SubjectRef memory s = _account(alice);

        allowEvaluator.set(Match.MATCH);
        assertEq(_assess(deferring, s, alice).disposition, Disposition.PROCEED);
        allowEvaluator.set(Match.NO_MATCH);
        assertEq(_assess(deferring, s, alice).disposition, Disposition.REFUSE);
        allowEvaluator.set(Match.UNDETERMINED);
        assertEq(_assess(deferring, s, alice).disposition, Disposition.DEFER);
        assertEq(_assess(refusing, s, alice).disposition, Disposition.REFUSE);
        assertEq(_assess(lenient, s, alice).disposition, Disposition.PROCEED_RESTRICTED);
    }

    function test_proceedingOnTheUndetermined_staysOnRecordAsUndetermined() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        c.onIndeterminate = Disposition.PROCEED_RESTRICTED;
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.UNDETERMINED);
        SubjectRef memory s = _account(alice);

        vm.expectEmit(true, true, true, false, address(guard));
        emit IAWFGuard.Assessed(
            id, _key(s), JOIN, CONTEXT, alice, Outcome.INDETERMINATE, Disposition.PROCEED_RESTRICTED, R_UNDETERMINED_INPUT, 1, bytes32(0), 0
        );
        (Disposition d, Outcome o, bytes32 reason) = _act(id, JOIN, s, alice);
        // The adopter chose to go ahead. The record does not say the subject was verified.
        assertEq(d, Disposition.PROCEED_RESTRICTED);
        assertEq(o, Outcome.INDETERMINATE);
        assertEq(reason, R_UNDETERMINED_INPUT);
        assertEq(venue.done(CONTEXT, JOIN, _key(s)), 1);
    }

    function test_enforce_isForTheConsumerOnly() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        vm.prank(mallory);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.enforce(id, _account(alice), alice, JOIN, CONTEXT, new bytes[](0));
    }

    function test_enforce_recordsWhatAssessReturns() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        allowEvaluator.set(Match.MATCH);
        allowEvaluator.setValidUntil(uint64(T0 + 500));
        SubjectRef memory s = _account(alice);
        Assessment memory a = _assess(id, s, alice);
        vm.expectEmit(address(guard));
        emit IAWFGuard.Assessed(
            id, _key(s), JOIN, CONTEXT, alice, Outcome.ALLOW, Disposition.PROCEED, R_ALLOW_MATCH, 1, a.stateDigest, uint64(T0 + 500)
        );
        (Disposition d, Outcome o, bytes32 reason) = _act(id, JOIN, s, alice);
        assertEq(d, a.disposition);
        assertEq(o, a.outcome);
        assertEq(reason, a.reason);
    }

    function test_refusal_isOnRecordToo() public {
        bytes32 id = _adopt(_config(_one(allowList), _none()));
        allowEvaluator.set(Match.NO_MATCH);
        SubjectRef memory s = _account(alice);
        (Disposition d,,) = _act(id, JOIN, s, alice);
        assertEq(d, Disposition.REFUSE);
        assertEq(venue.done(CONTEXT, JOIN, _key(s)), 0);
    }

    // ------------------------------------------------------------ versions and validity

    function test_pinnedList_stopsWhenItsStateMoves() public {
        bytes32 members = _list(Polarity.ALLOW);
        _add(members, _account(alice));
        BindingConfig memory c = _config(_one(members), _none());
        c.allow[0].pin = _state(members);
        bytes32 id = _adopt(c);
        _expect(_assess(id, _account(alice), alice), Outcome.ALLOW, R_ALLOW_MATCH);

        // Somebody takes over the list and adds an account. The adopter agreed to the earlier state.
        _add(members, _account(mallory));
        Assessment memory a = _assess(id, _account(mallory), mallory);
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[0], Match.UNDETERMINED, R_LIST_STATE_CHANGED);
        _expect(_assess(id, _account(alice), alice), Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);

        c.allow[0].pin = _state(members);
        vm.prank(adopter);
        guard.amend(id, c, "");
        _expect(_assess(id, _account(mallory), mallory), Outcome.ALLOW, R_ALLOW_MATCH);
    }

    function test_earlierAssessment_isNotCurrentAfterARevocation() public {
        bytes32 members = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        _add(members, s);
        bytes32 id = _adopt(_config(_one(members), _none()));
        Assessment memory a = _assess(id, s, alice);
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.stateDigest, guard.stateDigestOf(id));
        assertTrue(guard.isCurrent(id, a.stateDigest, a.validUntil));

        _revoke(members, s);
        // What was shown earlier is still a true record of then. It is no longer a ground to act on.
        assertFalse(guard.isCurrent(id, a.stateDigest, a.validUntil));
        _expect(_assess(id, s, alice), Outcome.DENY, R_DEFAULT);
    }

    function test_earlierAssessment_expiresWithItsFindings() public {
        bytes32 members = _list(Polarity.ALLOW);
        bytes32 barred = _list(Polarity.DENY);
        SubjectRef memory s = _account(alice);
        EntryInput memory input = _input();
        input.validUntil = uint64(T0 + 100);
        vm.prank(manager);
        registry.addEntry(members, s, input, "");
        bytes32 id = _adopt(_config(_one(members), _one(barred)));

        Assessment memory a = _assess(id, s, alice);
        assertEq(a.validUntil, T0 + 99); // the earliest of the findings
        vm.warp(T0 + 99);
        assertTrue(guard.isCurrent(id, a.stateDigest, a.validUntil));
        vm.warp(T0 + 100);
        assertFalse(guard.isCurrent(id, a.stateDigest, a.validUntil)); // no list changed; time did
        _expect(_assess(id, s, alice), Outcome.DENY, R_DEFAULT);
    }

    function test_unreachableRegistry_isUndetermined() public {
        AWFRegistry other = new AWFRegistry();
        ListConfig memory lc = _listConfig(Polarity.DENY, Mode.ENUMERATED);
        vm.prank(manager);
        bytes32 foreign = other.createList(lc, "");
        BindingConfig memory c = _config(_one(allowList), _none());
        c.deny = new ListRef[](1);
        c.deny[0] = ListRef(address(other), foreign, bytes32(0));
        c.denyThreshold = 1;
        bytes32 id = _adopt(c);
        allowEvaluator.set(Match.MATCH);
        _expect(_assess(id, _account(alice), alice), Outcome.ALLOW, R_ALLOW_MATCH);

        vm.etch(address(other), hex"fe"); // the registry stops answering
        Assessment memory a = _assess(id, _account(alice), alice);
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[1], Match.UNDETERMINED, R_REGISTRY_UNAVAILABLE);
    }

    function test_evidence_goesToTheListAtItsPosition() public {
        ListConfig memory lc = _listConfig(Polarity.DENY, Mode.COMMITTED);
        vm.prank(manager);
        bytes32 committed = registry.createList(lc, "");
        bytes32[] memory keys = new bytes32[](3);
        keys[1] = _key(_account(mallory));
        keys[2] = bytes32(type(uint256).max);
        bytes32[][] memory levels = SetTree.build(keys);
        vm.prank(manager);
        registry.commitSet(committed, SetTree.root(levels), SetKind.SORTED, 3, "");

        bytes32 id = _adopt(_config(_one(allowList), _one(committed)));
        allowEvaluator.set(Match.MATCH);
        SubjectRef memory s = _account(alice);
        uint256 low = _key(s) < keys[1] ? 0 : 1;
        bytes memory proof = SetTree.absenceProof(levels, keys, low);

        Assessment memory a = _assess(id, s, alice, _evidence("", proof));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        _expect(a.findings[1], Match.NO_MATCH, R_SET_NON_MEMBER);
        // Without the proof the deny side is open, and the request is not let through.
        a = _assess(id, s, alice);
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[1], Match.UNDETERMINED, R_PROOF_MISSING);
    }

    // ------------------------------------------------------------ work in progress

    function test_admission_isHonouredForItsContextUntilWithdrawn() public {
        bytes32 members = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        _add(members, s);
        BindingConfig memory c = _config(_one(members), _none());
        c.actions = new ActionRule[](2);
        c.actions[0] = ActionRule(JOIN, false); // taking on new work: decided every time
        c.actions[1] = ActionRule(ACCESS, true); // continuing admitted work: decided once per context
        bytes32 id = _adopt(c);

        vm.expectEmit(address(guard));
        emit IAWFGuard.AdmissionRecorded(id, _key(s), ACCESS, CONTEXT, Outcome.ALLOW);
        (Disposition d,,) = _act(id, ACCESS, s, alice);
        assertEq(d, Disposition.PROCEED);
        Admission memory admission = guard.admissionOf(id, CONTEXT, _key(s), ACCESS);
        assertEq(admission.at, T0);
        assertEq(admission.outcome, Outcome.ALLOW);

        _revoke(members, s);
        bytes32 reason;
        // New work stops at once.
        (d,, reason) = _act(id, JOIN, s, alice);
        assertEq(d, Disposition.REFUSE);
        assertEq(reason, R_DEFAULT);
        // Work admitted before goes on under the rule the adopter declared for it.
        (d,, reason) = _act(id, ACCESS, s, alice);
        assertEq(d, Disposition.PROCEED);
        assertEq(reason, R_ADMISSION_HONOURED);
        // The admission is the subject's, and standing is checked on every use.
        (d,, reason) = _act(id, ACCESS, s, mallory);
        assertEq(d, Disposition.REFUSE);
        assertEq(reason, R_PRESENTER_NOT_AUTHORIZED);
        // Another context has no admission.
        vm.prank(alice);
        (d,,) = venue.act(id, ACCESS, keccak256("context/2"), s, new bytes[](0));
        assertEq(d, Disposition.PROCEED); // not covered by this binding: NOT_APPLICABLE, which this adopter lets pass

        // Ending admitted work is a decision of its own, taken by the adopter.
        vm.prank(mallory);
        vm.expectRevert(IAWFGuard.NotAuthorized.selector);
        guard.withdrawAdmission(id, CONTEXT, _key(s), ACCESS);
        vm.expectEmit(address(guard));
        emit IAWFGuard.AdmissionWithdrawn(id, _key(s), ACCESS, CONTEXT);
        vm.prank(adopter);
        guard.withdrawAdmission(id, CONTEXT, _key(s), ACCESS);
        (d,, reason) = _act(id, ACCESS, s, alice);
        assertEq(d, Disposition.REFUSE);
        assertEq(reason, R_DEFAULT);
    }

    function test_admission_isNotGivenByARefusal() public {
        BindingConfig memory c = _config(_one(allowList), _none());
        c.actions[0] = ActionRule(JOIN, true);
        bytes32 id = _adopt(c);
        SubjectRef memory s = _account(alice);
        allowEvaluator.set(Match.NO_MATCH);
        _act(id, JOIN, s, alice);
        assertEq(guard.admissionOf(id, CONTEXT, _key(s), JOIN).at, 0);
        allowEvaluator.set(Match.MATCH);
        (Disposition d,,) = _act(id, JOIN, s, alice);
        assertEq(d, Disposition.PROCEED);
        assertEq(guard.admissionOf(id, CONTEXT, _key(s), JOIN).at, T0);
    }
}
