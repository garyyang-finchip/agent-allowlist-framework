// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AAFBase.sol";
import {
    AAFCredentialHistoryEvaluator,
    IAssertionSource,
    ITaskLedger
} from "../assets/erc-8507/contracts/adapters/AAFCredentialHistoryEvaluator.sol";
import {AAFBoundAnchorRelation} from "../assets/erc-8507/contracts/adapters/AAFBoundAnchorRelation.sol";
import {AssertionFixture} from "./fixtures/AssertionFixture.sol";
import {TaskLedgerFixture} from "./fixtures/TaskLedgerFixture.sol";
import {AIDRegistry} from "./vendor/aid/AIDRegistry.sol";
import {IKYARegistry} from "./vendor/kya/IKYARegistry.sol";
import {ITaskTender} from "./vendor/task/ITaskTender.sol";

/// @dev Case A of the specification: who may bid for a task is decided by criteria.
contract AAFCaseATest is AAFBase {
    bytes32 internal constant SCHEME = keccak256("scheme/delivery-capability/1");
    bytes32 internal constant TASK = bytes32(uint256(7));

    AssertionFixture internal assertions;
    TaskLedgerFixture internal ledger;
    AAFCredentialHistoryEvaluator internal evaluator;
    address internal issuer = makeAddr("issuer");
    bytes32 internal qualified;
    bytes32 internal binding;
    uint256 internal agentA; // alice
    uint256 internal agentB; // bob

    function setUp() public override {
        super.setUp();
        assertions = new AssertionFixture();
        ledger = new TaskLedgerFixture();
        address[] memory issuers = new address[](1);
        issuers[0] = issuer;
        // Level 2 from the accepted issuer, and two accepted deliveries within ninety days.
        evaluator = new AAFCredentialHistoryEvaluator(address(assertions), SCHEME, 2, issuers, address(ledger), 2, 90 days);

        bytes32 criteriaId =
            registry.registerCriteria(keccak256("criteria document"), address(evaluator), evaluator.configHash(), 0, "");
        ListConfig memory lc = _listConfig(Polarity.ALLOW, Mode.PREDICATE);
        lc.criteriaId = criteriaId;
        vm.prank(manager);
        qualified = registry.createList(lc, "");

        BindingConfig memory c = _config(_one(qualified), _none());
        c.scope.context = TASK;
        c.actions[0] = ActionRule(BID, Reuse.NONE);
        c.onNotApplicable = Disposition.REFUSE;
        binding = _adopt(c);

        vm.prank(alice);
        agentA = identities.register();
        vm.prank(bob);
        agentB = identities.register();
        _attest(agentA, 2, uint64(T0 + 30 days), true);
        _attest(agentB, 1, uint64(T0 + 30 days), true);
        vm.startPrank(alice);
        ledger.record(11, 1, 1);
        ledger.record(12, 1, 1);
        ledger.record(13, 1, 0); // still pending
        ledger.record(14, 1, 2); // rejected
        vm.stopPrank();
        vm.startPrank(bob);
        ledger.record(21, 1, 1);
        ledger.record(22, 1, 1);
        vm.stopPrank();
    }

    function _attest(uint256 agentId, uint8 level, uint64 expiresAt, bool bindController) internal {
        IAssertionSource.Subject memory s = IAssertionSource.Subject(
            keccak256("erc8004"), abi.encode(block.chainid, address(identities), agentId)
        );
        vm.prank(issuer);
        assertions.attest(s, SCHEME, level, expiresAt, bindController);
    }

    function _refs(uint256 a, uint256 b) internal pure returns (bytes memory) {
        AAFCredentialHistoryEvaluator.TaskRef[] memory refs = new AAFCredentialHistoryEvaluator.TaskRef[](2);
        refs[0] = AAFCredentialHistoryEvaluator.TaskRef(a, 1);
        refs[1] = AAFCredentialHistoryEvaluator.TaskRef(b, 1);
        return abi.encode(refs);
    }

    function _bid(uint256 agentId, address presenter, bytes memory history) internal view returns (Assessment memory) {
        return guard.assess(binding, _entry(address(identities), agentId), presenter, BID, TASK, _evidence(history));
    }

    function test_caseA_qualifiedAgentBids() public {
        Assessment memory a = _bid(agentA, alice, _refs(11, 12));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        _expect(a.findings[0], Match.MATCH, "CRITERIA_MET");
        // The credential can be revoked before it expires and no list changes when it is, so the
        // result is for this use only. It carries no period during which it could be used again.
        assertEq(a.findings[0].validUntil, 0);
        assertEq(a.validUntil, 0);

        vm.prank(alice);
        (Disposition d,,) = venue.act(binding, BID, TASK, _entry(address(identities), agentA), _evidence(_refs(11, 12)));
        assertEq(d, Disposition.PROCEED);
        assertEq(venue.done(TASK, BID, _key(_entry(address(identities), agentA))), 1);
    }

    function test_caseA_notMeetingTheCriteria_isRefusedWithoutBeingOnADenyList() public view {
        Assessment memory a = _bid(agentB, bob, _refs(21, 22));
        _expect(a, Outcome.DENY, R_DEFAULT); // refused by the default rule of an allow-only binding
        _expect(a.findings[0], Match.NO_MATCH, "CREDENTIAL_NOT_VALID");
        assertEq(a.denySide, Match.NO_MATCH); // nothing puts the agent on a deny list
    }

    function test_caseA_historyMustBePresented() public view {
        Assessment memory a = _bid(agentA, alice, "");
        // The criteria make presenting the history a condition, so its absence is a settled no.
        _expect(a, Outcome.DENY, R_DEFAULT);
        _expect(a.findings[0], Match.NO_MATCH, "EVIDENCE_NOT_PRESENTED");
    }

    function test_caseA_insufficientHistory() public view {
        Assessment memory a = _bid(agentA, alice, _refs(11, 13)); // one accepted, one pending
        _expect(a.findings[0], Match.NO_MATCH, "HISTORY_INSUFFICIENT");
        a = _bid(agentA, alice, _refs(11, 14)); // one accepted, one rejected
        _expect(a.findings[0], Match.NO_MATCH, "HISTORY_INSUFFICIENT");
        a = _bid(agentA, alice, _refs(21, 22)); // somebody else's deliveries
        _expect(a.findings[0], Match.NO_MATCH, "HISTORY_INSUFFICIENT");
    }

    function test_caseA_theSameDeliveryIsNotCountedTwice() public view {
        Assessment memory a = _bid(agentA, alice, _refs(11, 11));
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[0], Match.UNDETERMINED, "EVIDENCE_MALFORMED");
        assertEq(a.disposition, Disposition.DEFER);
    }

    function test_caseA_unreadableSource_isNotAFindingAboutTheAgent() public {
        assertions.setUnavailable(true);
        Assessment memory a = _bid(agentA, alice, _refs(11, 12));
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[0], Match.UNDETERMINED, "SOURCE_UNAVAILABLE");
        assertEq(a.disposition, Disposition.DEFER); // held for later, not refused as unqualified
        assertions.setUnavailable(false);
        ledger.setUnavailable(true);
        _expect(_bid(agentA, alice, _refs(11, 12)).findings[0], Match.UNDETERMINED, "SOURCE_UNAVAILABLE");
    }

    function test_caseA_expiry() public {
        Assessment memory a = _bid(agentA, alice, _refs(11, 12));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        vm.warp(T0 + 30 days);
        // No list changed. The next use is decided on what is true then, and the answer is no.
        _expect(_bid(agentA, alice, _refs(11, 12)).findings[0], Match.NO_MATCH, "CREDENTIAL_NOT_VALID");
    }

    function test_caseA_revocationBeforeExpiry_takesEffectAtTheNextUse() public {
        SubjectRef memory s = _entry(address(identities), agentA);
        Assessment memory a = _bid(agentA, alice, _refs(11, 12));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        bytes32 digest = guard.stateDigestOf(binding);

        // The issuer revokes the credential twenty-nine days before it would have expired.
        IAssertionSource.Subject memory subject =
            IAssertionSource.Subject(keccak256("erc8004"), abi.encode(block.chainid, address(identities), agentA));
        vm.prank(issuer);
        assertions.revoke(subject, SCHEME);

        // Neither the list nor the binding changed, so their digest cannot show the revocation.
        assertEq(guard.stateDigestOf(binding), digest);
        assertEq(a.stateDigest, digest);
        // That is why the earlier result was valid for its use only and is not current now.
        assertEq(a.validUntil, 0);
        assertFalse(guard.isCurrent(binding, a.stateDigest, a.validUntil));

        // The next use reads the credential again and is refused.
        Assessment memory b = _bid(agentA, alice, _refs(11, 12));
        _expect(b, Outcome.DENY, R_DEFAULT);
        _expect(b.findings[0], Match.NO_MATCH, "CREDENTIAL_NOT_VALID");
        vm.prank(alice);
        (Disposition d,,) = venue.act(binding, BID, TASK, s, _evidence(_refs(11, 12)));
        assertEq(d, Disposition.REFUSE);
    }

    function test_caseA_historyAgesOut() public {
        _attest(agentA, 2, 0, true); // a credential without expiry
        Assessment memory a = _bid(agentA, alice, _refs(11, 12));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        vm.warp(T0 + 90 days);
        _expect(_bid(agentA, alice, _refs(11, 12)).findings[0], Match.NO_MATCH, "HISTORY_INSUFFICIENT");
    }

    function test_caseA_revokedCredential() public {
        IAssertionSource.Subject memory s = IAssertionSource.Subject(
            keccak256("erc8004"), abi.encode(block.chainid, address(identities), agentA)
        );
        vm.prank(issuer);
        assertions.revoke(s, SCHEME);
        _expect(_bid(agentA, alice, _refs(11, 12)).findings[0], Match.NO_MATCH, "CREDENTIAL_NOT_VALID");
    }

    function test_caseA_changeOfController() public {
        vm.prank(alice);
        identities.transferFrom(alice, carol, agentA);
        // The former owner no longer acts for the identity.
        _expect(_bid(agentA, alice, _refs(11, 12)), Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        // The new owner holds the identity. The credential was bound to the controller it was issued for.
        Assessment memory a = _bid(agentA, carol, _refs(11, 12));
        assertEq(a.standing, Match.MATCH);
        assertEq(a.controller, carol);
        _expect(a, Outcome.DENY, R_DEFAULT);
        _expect(a.findings[0], Match.NO_MATCH, "CREDENTIAL_NOT_VALID");
        // With a credential bound to the identity itself, the history still belongs to the former controller.
        _attest(agentA, 2, 0, false);
        _expect(_bid(agentA, carol, _refs(11, 12)).findings[0], Match.NO_MATCH, "HISTORY_INSUFFICIENT");
    }

    function test_caseA_anotherTaskIsOutsideTheBinding() public view {
        Assessment memory a = guard.assess(
            binding, _entry(address(identities), agentA), alice, BID, bytes32(uint256(8)), _evidence(_refs(11, 12))
        );
        _expect(a, Outcome.NOT_APPLICABLE, R_CONTEXT_NOT_COVERED);
        assertEq(a.disposition, Disposition.REFUSE);
    }

    function test_caseA_otherSubjectKinds_areNotDecidedByThisEvaluator() public view {
        Assessment memory a = guard.assess(binding, _account(alice), alice, BID, TASK, _evidence(_refs(11, 12)));
        _expect(a.findings[0], Match.UNDETERMINED, "SUBJECT_UNSUPPORTED");
    }

    function test_caseA_changedThresholds_areAnotherVersion() public {
        address[] memory issuers = new address[](1);
        issuers[0] = issuer;
        AAFCredentialHistoryEvaluator stricter =
            new AAFCredentialHistoryEvaluator(address(assertions), SCHEME, 3, issuers, address(ledger), 2, 90 days);
        assertTrue(stricter.configHash() != evaluator.configHash());
        // Criteria that name a rule the evaluator does not run decide nothing.
        bytes32 mismatched =
            registry.registerCriteria(keccak256("criteria document"), address(stricter), evaluator.configHash(), 0, "");
        vm.prank(manager);
        registry.setCriteria(qualified, mismatched);
        _expect(_bid(agentA, alice, _refs(11, 12)).findings[0], Match.UNDETERMINED, "RULE_UNKNOWN");
    }

    function test_caseA_narrowViewsHaveTheSelectorsOfTheFullInterfaces() public pure {
        assertEq(IAssertionSource.resolve.selector, IKYARegistry.resolve.selector);
        assertEq(ITaskLedger.submissionOf.selector, ITaskTender.submissionOf.selector);
    }
}

/// @dev Case B of the specification: a group refuses listed agents, with notice, and decides
/// separately whether the refusal reaches the accounts bound to them.
contract AAFCaseBTest is AAFBase {
    bytes32 internal constant SWARM = keccak256("swarm/alpha");

    AIDRegistry internal anchors;
    AAFBoundAnchorRelation internal relation;
    bytes32 internal barred;
    bytes32 internal barredAnchors;
    bytes32 internal binding;
    BindingConfig internal config;
    uint256 internal agentId;
    SubjectRef internal agent;
    address internal operator = makeAddr("operator");

    function setUp() public override {
        super.setUp();
        anchors = new AIDRegistry(90 days, 365 days);
        relation = new AAFBoundAnchorRelation(address(anchors));

        ListConfig memory lc = _listConfig(Polarity.DENY, Mode.ENUMERATED);
        lc.noticePeriod = 2 days;
        vm.prank(manager);
        barred = registry.createList(lc, "");
        barredAnchors = _derivedList(
            barred,
            registry.registerCriteria(keccak256("extension"), address(relation), relation.RELATION_BOUND_ANCHOR(), 1, ""),
            bytes32(0)
        );

        vm.startPrank(operator);
        agentId = identities.register();
        anchors.bind(address(identities), agentId);
        vm.stopPrank();
        agent = _entry(address(identities), agentId);

        BindingConfig memory c = _config(_none(), _one(barred));
        c.scope.context = SWARM;
        c.onNoMatch = Outcome.ALLOW;
        config = c;
        binding = _adopt(c);
    }

    function _join(SubjectRef memory s, address presenter) internal view returns (Assessment memory) {
        return guard.assess(binding, s, presenter, JOIN, SWARM, new bytes[](0));
    }

    function _bar(SubjectRef memory s) internal {
        EntryInput memory input = _input();
        input.basis = Basis.EVIDENCED;
        input.basisHash = keccak256("incident report");
        input.reason = "BREACH_OF_CHARTER";
        vm.prank(manager);
        registry.addEntry(barred, s, input, "ipfs://incident-report");
    }

    function test_caseB_noticeObjectionEffect() public {
        _expect(_join(agent, operator), Outcome.ALLOW, R_DEFAULT);
        _bar(agent);

        // During the notice period the entry is on record and not yet in effect.
        Assessment memory a = _join(agent, operator);
        _expect(a, Outcome.ALLOW, R_DEFAULT);
        _expect(a.findings[0], Match.NO_MATCH, R_ENTRY_PENDING);
        // The list says until when its answer holds: the moment before the entry takes effect.
        assertEq(a.findings[0].validUntil, T0 + 2 days - 1);
        // Joining is decided at every use, so the assessment itself is not for later use.
        assertEq(a.validUntil, 0);

        // The listed side objects. The objection is recorded and by itself changes nothing.
        vm.prank(operator);
        registry.fileObjection(barred, _key(agent), keccak256("objection"), "ipfs://objection");
        vm.warp(T0 + 2 days);
        a = _join(agent, operator);
        _expect(a, Outcome.DENY, R_DENY_MATCH);
        assertEq(a.findings[0].basis, keccak256("incident report"));

        // The manager reviews: suspension lifts the effect, resumption restores it, revocation ends it.
        vm.prank(manager);
        registry.suspendEntry(barred, _key(agent), "UNDER_REVIEW");
        _expect(_join(agent, operator), Outcome.ALLOW, R_DEFAULT);
        vm.prank(manager);
        registry.resumeEntry(barred, _key(agent), "REVIEW_CLOSED");
        _expect(_join(agent, operator), Outcome.DENY, R_DENY_MATCH);
        vm.prank(manager);
        registry.revokeEntry(barred, _key(agent), "OBJECTION_UPHELD");
        _expect(_join(agent, operator), Outcome.ALLOW, R_DEFAULT);
    }

    function test_caseB_extensionAppliesOnlyWhereItIsAdopted() public {
        _bar(agent);
        vm.warp(T0 + 2 days);
        SubjectRef memory account = _account(operator);

        // The agent identity is refused. Its operator's account is another object, and this binding
        // did not adopt any extension to related objects.
        _expect(_join(agent, operator), Outcome.DENY, R_DENY_MATCH);
        _expect(_join(account, operator), Outcome.ALLOW, R_DEFAULT);

        // The swarm decides to adopt the extension, as a second list, and its binding says so.
        BindingConfig memory c = config;
        c.deny = new ListRef[](2);
        c.deny[0] = ListRef(address(registry), barred, bytes32(0));
        c.deny[1] = ListRef(address(registry), barredAnchors, bytes32(0));
        vm.prank(adopter);
        guard.amend(binding, c, "");

        Assessment memory a = _join(account, operator);
        _expect(a, Outcome.DENY, R_DENY_MATCH);
        assertEq(a.bindingVersion, 2);
        _expect(a.findings[0], Match.NO_MATCH, R_NOT_LISTED);
        _expect(a.findings[1], Match.MATCH, R_RELATED);
        assertEq(a.findings[1].derivedFrom, _key(agent));
        assertEq(a.validUntil, 0); // a derived refusal is read fresh each time

        // An unrelated account is confirmed unrelated and joins.
        _expect(_join(_account(bob), bob), Outcome.ALLOW, R_DEFAULT);
    }

    function test_caseB_extensionNeedsEvidenceFromBothSides() public {
        _bar(agent);
        vm.warp(T0 + 2 days);
        BindingConfig memory c = config;
        c.deny = new ListRef[](2);
        c.deny[0] = ListRef(address(registry), barred, bytes32(0));
        c.deny[1] = ListRef(address(registry), barredAnchors, bytes32(0));
        vm.prank(adopter);
        guard.amend(binding, c, "");

        // The operator retires its anchor and names an uninvolved account as successor.
        vm.prank(operator);
        anchors.retire(carol);
        _expect(_join(_account(carol), carol), Outcome.ALLOW, R_DEFAULT);

        // An account that takes the identity over and binds itself to it is related by its own act.
        vm.prank(operator);
        identities.transferFrom(operator, bob, agentId);
        vm.prank(bob);
        anchors.bind(address(identities), agentId);
        Assessment memory a = _join(_account(bob), bob);
        _expect(a, Outcome.DENY, R_DENY_MATCH);
        assertEq(a.findings[1].derivedFrom, _key(agent));

        // When the identity leaves the list, the derived refusal goes with it.
        vm.prank(manager);
        registry.revokeEntry(barred, _key(agent), "WITHDRAWN");
        _expect(_join(_account(bob), bob), Outcome.ALLOW, R_DEFAULT);
    }

    function test_caseB_refusalIsEnforcedAndRecorded() public {
        _bar(agent);
        vm.warp(T0 + 2 days);
        vm.expectEmit(true, true, true, false, address(guard));
        emit IAAFGuard.Assessed(
            binding, _key(agent), JOIN, SWARM, operator, Outcome.DENY, Disposition.REFUSE, R_DENY_MATCH, 1, bytes32(0), 0
        );
        vm.prank(operator);
        (Disposition d, Outcome o,) = venue.act(binding, JOIN, SWARM, agent, new bytes[](0));
        assertEq(d, Disposition.REFUSE);
        assertEq(o, Outcome.DENY);
        assertEq(venue.done(SWARM, JOIN, _key(agent)), 0);
    }
}

/// @dev Case C of the specification: a service combines an allow list with two deny lists.
contract AAFCaseCTest is AAFBase {
    bytes32 internal constant SERVICE = keccak256("service/inference-gateway");

    bytes32 internal partners; // ALLOW, enumerated
    bytes32 internal barred; // DENY, enumerated
    bytes32 internal sanctioned; // DENY, committed, sorted
    bytes32 internal binding;
    bytes32[] internal keys;
    bytes32[][] internal levels;

    function setUp() public override {
        super.setUp();
        partners = _list(Polarity.ALLOW);
        barred = _list(Polarity.DENY);
        ListConfig memory lc = _listConfig(Polarity.DENY, Mode.COMMITTED);
        vm.prank(manager);
        sanctioned = registry.createList(lc, "");

        bytes32[] memory k = new bytes32[](3);
        k[1] = _key(_account(makeAddr("sanctioned account")));
        k[2] = bytes32(type(uint256).max);
        _commit(k);

        _add(partners, _account(alice));
        _add(partners, _account(bob));
        _add(barred, _account(bob));

        BindingConfig memory c = _config(_one(partners), _two(barred, sanctioned));
        c.scope.context = SERVICE;
        c.actions[0] = ActionRule(INVOKE, Reuse.WHILE_CURRENT);
        binding = _adopt(c);
    }

    function _commit(bytes32[] memory k) internal {
        keys = k;
        bytes32[][] memory l = SetTree.build(k);
        delete levels;
        for (uint256 i; i < l.length; ++i) levels.push(l[i]);
        vm.prank(manager);
        registry.commitSet(sanctioned, SetTree.root(l), SetKind.SORTED, uint64(k.length), "");
    }

    function _absent(SubjectRef memory s) internal view returns (bytes memory) {
        uint256 low;
        while (keys[low + 1] < _key(s)) ++low;
        return SetTree.absenceProof(levels, keys, low);
    }

    /// @dev Evidence in binding order: partners, barred, sanctioned.
    function _invoke(SubjectRef memory s, address presenter, bytes memory proof) internal view returns (Assessment memory) {
        bytes[] memory e = new bytes[](3);
        e[2] = proof;
        return guard.assess(binding, s, presenter, INVOKE, SERVICE, e);
    }

    function test_caseC_listedAndClear_isAllowed() public view {
        SubjectRef memory s = _account(alice);
        Assessment memory a = _invoke(s, alice, _absent(s));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertEq(a.allowSide, Match.MATCH);
        assertEq(a.denySide, Match.NO_MATCH);
        _expect(a.findings[2], Match.NO_MATCH, R_SET_NON_MEMBER);
    }

    function test_caseC_conflict_denyWinsAsDeclared() public view {
        SubjectRef memory s = _account(bob);
        _expect(_invoke(s, bob, _absent(s)), Outcome.DENY, R_CONFLICT);
        // The deny side is already met by one list; the open question about the other cannot change it.
        _expect(_invoke(s, bob, ""), Outcome.DENY, R_CONFLICT);
    }

    function test_caseC_noMatch_isRefusedByDefaultOnly() public view {
        SubjectRef memory s = _account(carol);
        Assessment memory a = _invoke(s, carol, _absent(s));
        _expect(a, Outcome.DENY, R_DEFAULT);
        assertEq(a.denySide, Match.NO_MATCH); // not being on the allow list put her on no deny list
        // Without the proof the deny side is open, and either way the answer is the same refusal.
        _expect(_invoke(s, carol, ""), Outcome.DENY, R_DEFAULT);
    }

    function test_caseC_unknown_isNotAPass() public view {
        SubjectRef memory s = _account(alice);
        Assessment memory a = _invoke(s, alice, "");
        // On the allow list, and nothing shows she is absent from the committed deny list.
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        assertEq(a.denySide, Match.UNDETERMINED);
        _expect(a.findings[2], Match.UNDETERMINED, R_PROOF_MISSING);
        assertEq(a.disposition, Disposition.DEFER);
    }

    function test_caseC_borrowedIdentity_isRefused() public view {
        SubjectRef memory s = _account(alice);
        Assessment memory a = _invoke(s, mallory, _absent(s));
        _expect(a, Outcome.DENY, R_PRESENTER_NOT_AUTHORIZED);
        assertEq(a.standing, Match.NO_MATCH);
    }

    function test_caseC_earlierResultAfterRevocation() public {
        SubjectRef memory s = _account(alice);
        Assessment memory a = _invoke(s, alice, _absent(s));
        _expect(a, Outcome.ALLOW, R_ALLOW_MATCH);
        assertTrue(guard.isCurrent(binding, a.stateDigest, a.validUntil));

        _revoke(partners, s);
        assertFalse(guard.isCurrent(binding, a.stateDigest, a.validUntil));
        _expect(_invoke(s, alice, _absent(s)), Outcome.DENY, R_DEFAULT);
    }

    function test_caseC_earlierProofAfterANewSet() public {
        SubjectRef memory s = _account(alice);
        bytes memory oldProof = _absent(s);
        _expect(_invoke(s, alice, oldProof), Outcome.ALLOW, R_ALLOW_MATCH);

        // The sanctions set now contains alice. A proof against the earlier root shows nothing.
        bytes32[] memory k = new bytes32[](4);
        bytes32 a1 = keys[1];
        bytes32 a2 = _key(s);
        (k[1], k[2]) = a1 < a2 ? (a1, a2) : (a2, a1);
        k[3] = bytes32(type(uint256).max);
        _commit(k);

        Assessment memory a = _invoke(s, alice, oldProof);
        _expect(a, Outcome.INDETERMINATE, R_UNDETERMINED_INPUT);
        _expect(a.findings[2], Match.UNDETERMINED, R_PROOF_INVALID);
        // Anyone can show her membership against the new root.
        uint256 index = k[1] == a2 ? 1 : 2;
        _expect(_invoke(s, alice, SetTree.memberProof(levels, index)), Outcome.DENY, R_CONFLICT);
    }

    function test_caseC_enforcedEndToEnd() public {
        SubjectRef memory s = _account(alice);
        bytes[] memory e = new bytes[](3);
        e[2] = _absent(s);
        vm.prank(alice);
        (Disposition d,,) = venue.act(binding, INVOKE, SERVICE, s, e);
        assertEq(d, Disposition.PROCEED);
        vm.prank(mallory);
        bytes32 reason;
        (d,, reason) = venue.act(binding, INVOKE, SERVICE, s, e);
        assertEq(d, Disposition.REFUSE);
        assertEq(reason, R_PRESENTER_NOT_AUTHORIZED);
        assertEq(venue.done(SERVICE, INVOKE, _key(s)), 1);
    }

    function test_caseC_objectsUnderTheSameService() public {
        // A second binding of the same consumer, about what is invoked instead of who invokes.
        bytes32 excludedTools = _list(Polarity.DENY);
        SubjectRef memory excluded = _artefact(keccak256("summarizer 2.0.1 package"));
        SubjectRef memory current = _artefact(keccak256("summarizer 2.0.2 package"));
        _add(excludedTools, excluded);
        BindingConfig memory c = _config(_none(), _one(excludedTools));
        c.scope.context = SERVICE;
        c.role = Role.OBJECT;
        c.onNoMatch = Outcome.ALLOW;
        c.actions[0] = ActionRule(keccak256("aaf.action.use-tool"), Reuse.NONE);
        bytes32 tools = _adopt(c);

        vm.startPrank(alice);
        (Disposition d,,) = venue.act(tools, keccak256("aaf.action.use-tool"), SERVICE, excluded, new bytes[](0));
        assertEq(d, Disposition.REFUSE);
        (d,,) = venue.act(tools, keccak256("aaf.action.use-tool"), SERVICE, current, new bytes[](0));
        assertEq(d, Disposition.PROCEED);
        vm.stopPrank();
        // Excluding a tool version says nothing about the agent that asked for it.
        SubjectRef memory s = _account(alice);
        _expect(_invoke(s, alice, _absent(s)), Outcome.ALLOW, R_ALLOW_MATCH);
    }
}
