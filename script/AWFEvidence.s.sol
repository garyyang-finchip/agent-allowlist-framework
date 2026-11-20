// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AWFRegistry} from "../assets/erc-9999/contracts/AWFRegistry.sol";
import {AWFGuard} from "../assets/erc-9999/contracts/AWFGuard.sol";
import {AWFExampleConsumer} from "../assets/erc-9999/contracts/examples/AWFExampleConsumer.sol";
import {
    AWFCredentialHistoryEvaluator,
    IAssertionSource
} from "../assets/erc-9999/contracts/adapters/AWFCredentialHistoryEvaluator.sol";
import {AWFBoundAnchorRelation} from "../assets/erc-9999/contracts/adapters/AWFBoundAnchorRelation.sol";
import "../assets/erc-9999/contracts/interfaces/AWFTypes.sol";
import {IdentityFixture} from "../test/fixtures/IdentityFixture.sol";
import {AssertionFixture} from "../test/fixtures/AssertionFixture.sol";
import {TaskLedgerFixture} from "../test/fixtures/TaskLedgerFixture.sol";
import {AIDRegistry} from "../test/vendor/aid/AIDRegistry.sol";

/// @notice Runs the three worked cases of the specification on a live network and records what
/// happened. Driven by scripts/evidence-run.sh, one phase per invocation:
///
///   deploy   registry, guard, the two example modules, three consumers, the stand-ins the cases
///            read from, gas for the accounts of the run
///   caseA1   Case A: criteria, list, binding, bids that are admitted and bids that are refused
///   caseB1   Case B up to the objection: a refusal entered with a notice period
///   caseA2   Case A: a credential that is about to expire is used while it is valid
///   (wait)   the notice period and the lifetime of that credential pass
///   caseA3   Case A: the same bid after expiry
///   caseB2   Case B: the refusal takes effect; the extension to bound accounts is adopted; revocation
///   caseC    Case C: allow list, deny list and committed deny set combined; excluded tool versions
///   report   reads the final state, checks it against the specification, writes evidence.json
///
/// Environment: NETWORK (anvil or sepolia), DEPLOYER_PK, and for the deploy phase GAS_PRICE_WEI
/// with one gas budget per account (GAS_MANAGER, GAS_ISSUER, GAS_ALICE, GAS_BOB, GAS_CAROL,
/// GAS_OPERATOR, GAS_MALLORY). The accounts are derived from DEPLOYER_PK;
/// deployments/<network>/plan.json (written by tools/awf.mjs plan) holds their addresses, the
/// document hashes and the committed set.
contract AWFEvidence is Script {
    string internal network;
    string internal dir;
    string internal plan;
    uint256 internal deployerPk;

    AWFRegistry internal registry;
    AWFGuard internal guard;
    IdentityFixture internal identities;
    AssertionFixture internal assertions;
    TaskLedgerFixture internal ledger;
    AIDRegistry internal anchors;
    AWFCredentialHistoryEvaluator internal evaluator;
    AWFBoundAnchorRelation internal relation;
    AWFExampleConsumer internal board;
    AWFExampleConsumer internal swarm;
    AWFExampleConsumer internal service;

    /// @dev Identifiers created along the way; kept in state.json between phases.
    struct Ids {
        uint256 agentA;
        uint256 agentB;
        uint256 agentS;
        bytes32 qualified;
        bytes32 bindingA;
        bytes32 barred;
        bytes32 barredAnchors;
        bytes32 bindingB;
        bytes32 partners;
        bytes32 barredC;
        bytes32 sanctioned;
        bytes32 excludedTools;
        bytes32 bindingC;
        bytes32 bindingTools;
        bytes32 earlierDigest;
        uint256 earlierValidUntil;
    }

    Ids internal ids;

    // ---------------------------------------------------------------- deploy

    function deploy() external {
        _init(false);
        uint256 gasPrice = vm.envUint("GAS_PRICE_WEI");
        address[] memory issuers = new address[](1);
        issuers[0] = _addr("issuer");

        vm.startBroadcast(deployerPk);
        registry = new AWFRegistry();
        guard = new AWFGuard();
        identities = new IdentityFixture();
        assertions = new AssertionFixture();
        ledger = new TaskLedgerFixture();
        anchors = new AIDRegistry(90 days, 365 days);
        evaluator = new AWFCredentialHistoryEvaluator(
            address(assertions),
            vm.parseJsonBytes32(plan, ".parameters.schemeId"),
            uint8(vm.parseJsonUint(plan, ".parameters.minLevel")),
            issuers,
            address(ledger),
            uint32(vm.parseJsonUint(plan, ".parameters.minAccepted")),
            uint64(vm.parseJsonUint(plan, ".parameters.window"))
        );
        relation = new AWFBoundAnchorRelation(address(anchors));
        // The deployer becomes the adopter of the three consumers.
        board = new AWFExampleConsumer(guard, "Task board");
        swarm = new AWFExampleConsumer(guard, "Swarm alpha membership");
        service = new AWFExampleConsumer(guard, "Inference gateway");
        _fund("manager", vm.envUint("GAS_MANAGER") * gasPrice);
        _fund("issuer", vm.envUint("GAS_ISSUER") * gasPrice);
        _fund("alice", vm.envUint("GAS_ALICE") * gasPrice);
        _fund("bob", vm.envUint("GAS_BOB") * gasPrice);
        _fund("carol", vm.envUint("GAS_CAROL") * gasPrice);
        _fund("operator", vm.envUint("GAS_OPERATOR") * gasPrice);
        _fund("mallory", vm.envUint("GAS_MALLORY") * gasPrice);
        vm.stopBroadcast();

        _save();
        console2.log("registry", address(registry));
        console2.log("guard   ", address(guard));
    }

    // ---------------------------------------------------------------- Case A

    function caseA1() external {
        _init(true);
        Scope memory scope = Scope(address(board), _ctx("task"), _doc("case_a_scope_json"));

        vm.startBroadcast(deployerPk);
        bytes32 scopeId = registry.declareScope(scope, _uri("case-a/scope.json"));
        bytes32 criteriaId = registry.registerCriteria(
            _doc("case_a_criteria_json"), address(evaluator), evaluator.configHash(), 0, _uri("case-a/criteria.json")
        );
        vm.stopBroadcast();

        ListConfig memory lc = _listConfig(Polarity.ALLOW, Mode.PREDICATE, scopeId, 1);
        lc.criteriaId = criteriaId;
        vm.startBroadcast(_pk("manager"));
        ids.qualified = registry.createList(lc, _uri("case-a/list-qualified.json"));
        vm.stopBroadcast();

        BindingConfig memory c = _binding(scope, _action("bid"), _doc("case_a_binding_json"));
        c.allow = _refs(ids.qualified);
        c.allowThreshold = 1;
        c.onNotApplicable = Disposition.REFUSE;
        vm.startBroadcast(deployerPk);
        ids.bindingA = guard.adopt(c, bytes32(0), _uri("case-a/binding.json"));
        vm.stopBroadcast();

        // Two agent identities, their credentials and their delivery histories.
        vm.startBroadcast(_pk("alice"));
        ids.agentA = identities.register();
        ledger.record(11, 1, 1);
        ledger.record(12, 1, 1);
        vm.stopBroadcast();
        vm.startBroadcast(_pk("bob"));
        ids.agentB = identities.register();
        ledger.record(21, 1, 1);
        ledger.record(22, 1, 1);
        vm.stopBroadcast();
        vm.startBroadcast(_pk("issuer"));
        assertions.attest(_credentialSubject(ids.agentA), evaluator.schemeId(), 2, uint64(block.timestamp + 30 days), true);
        assertions.attest(_credentialSubject(ids.agentB), evaluator.schemeId(), 1, uint64(block.timestamp + 30 days), true);
        vm.stopBroadcast();

        SubjectRef memory a = _entry(ids.agentA);
        SubjectRef memory b = _entry(ids.agentB);
        // 1. A qualified agent bids.
        _step(board, "alice", ids.bindingA, "bid", "task", a, _one(_history(11, 12)), Disposition.PROCEED, R_ALLOW_MATCH);
        // 2. Level 1 where level 2 is required: refused by the default of an allow-only binding.
        _step(board, "bob", ids.bindingA, "bid", "task", b, _one(_history(21, 22)), Disposition.REFUSE, R_DEFAULT);
        // 3. The history is a condition of these criteria and is not presented.
        _step(board, "alice", ids.bindingA, "bid", "task", a, _one(""), Disposition.REFUSE, R_DEFAULT);
        // 4. Somebody else names the qualified identity.
        _step(
            board, "mallory", ids.bindingA, "bid", "task", a, _one(_history(11, 12)), Disposition.REFUSE, R_PRESENTER_NOT_AUTHORIZED
        );
        // 5. The identity changes hands. The credential was bound to the former controller.
        vm.startBroadcast(_pk("alice"));
        identities.transferFrom(_addr("alice"), _addr("carol"), ids.agentA);
        vm.stopBroadcast();
        _step(board, "carol", ids.bindingA, "bid", "task", a, _one(_history(11, 12)), Disposition.REFUSE, R_DEFAULT);

        _save();
    }

    function caseA2() external {
        _init(true);
        // 6. A credential of level 2 that lasts a few minutes, used while it lasts.
        vm.startBroadcast(_pk("issuer"));
        assertions.attest(
            _credentialSubject(ids.agentB),
            evaluator.schemeId(),
            2,
            uint64(block.timestamp + vm.parseJsonUint(plan, ".parameters.credentialLifetime")),
            true
        );
        vm.stopBroadcast();
        _step(
            board, "bob", ids.bindingA, "bid", "task", _entry(ids.agentB), _one(_history(21, 22)), Disposition.PROCEED, R_ALLOW_MATCH
        );
    }

    function caseA3() external {
        _init(true);
        // 7. The same bid after the credential expired. No list changed.
        _step(board, "bob", ids.bindingA, "bid", "task", _entry(ids.agentB), _one(_history(21, 22)), Disposition.REFUSE, R_DEFAULT);
    }

    // ---------------------------------------------------------------- Case B

    function caseB1() external {
        _init(true);
        Scope memory scope = Scope(address(swarm), _ctx("swarm"), _doc("case_b_scope_json"));

        vm.startBroadcast(deployerPk);
        bytes32 scopeId = registry.declareScope(scope, _uri("case-b/scope.json"));
        bytes32 extension = registry.registerCriteria(
            _doc("case_b_criteria_extension_json"),
            address(relation),
            relation.RELATION_BOUND_ANCHOR(),
            1,
            _uri("case-b/criteria-extension.json")
        );
        vm.stopBroadcast();

        ListConfig memory lc = _listConfig(Polarity.DENY, Mode.ENUMERATED, scopeId, 2);
        lc.noticePeriod = uint32(vm.parseJsonUint(plan, ".parameters.noticePeriod"));
        vm.startBroadcast(_pk("manager"));
        ids.barred = registry.createList(lc, _uri("case-b/list-barred.json"));
        lc = _listConfig(Polarity.DENY, Mode.DERIVED, scopeId, 3);
        lc.criteriaId = extension;
        lc.source = ids.barred;
        ids.barredAnchors = registry.createList(lc, _uri("case-b/list-barred-anchors.json"));
        vm.stopBroadcast();

        BindingConfig memory c = _binding(scope, _action("join"), _doc("case_b_binding_json"));
        c.deny = _refs(ids.barred);
        c.denyThreshold = 1;
        c.onNoMatch = Outcome.ALLOW;
        vm.startBroadcast(deployerPk);
        ids.bindingB = guard.adopt(c, bytes32(0), _uri("case-b/binding.json"));
        vm.stopBroadcast();

        vm.startBroadcast(_pk("operator"));
        ids.agentS = identities.register();
        anchors.bind(address(identities), ids.agentS);
        vm.stopBroadcast();
        SubjectRef memory s = _entry(ids.agentS);

        // 1. Before anything is listed the agent joins.
        _step(swarm, "operator", ids.bindingB, "join", "swarm", s, _none(), Disposition.PROCEED, R_DEFAULT);
        // 2. The manager enters a refusal that states a fact and commits to its evidence.
        EntryInput memory input;
        input.basis = Basis.EVIDENCED;
        input.basisHash = _doc("case_b_basis_incident_json");
        input.reason = "BREACH_OF_CHARTER";
        vm.startBroadcast(_pk("manager"));
        registry.addEntry(ids.barred, s, input, _uri("case-b/basis-incident.json"));
        vm.stopBroadcast();
        // 3. During the notice period the entry is on record and has no effect yet.
        _step(swarm, "operator", ids.bindingB, "join", "swarm", s, _none(), Disposition.PROCEED, R_DEFAULT);
        // 4. The listed side objects. Nothing changes by that alone.
        vm.startBroadcast(_pk("operator"));
        registry.fileObjection(ids.barred, _key(s), keccak256("The delivery was made first by this agent."), "");
        vm.stopBroadcast();

        _save();
    }

    function caseB2() external {
        _init(true);
        Scope memory scope = Scope(address(swarm), _ctx("swarm"), _doc("case_b_scope_json"));
        SubjectRef memory s = _entry(ids.agentS);
        SubjectRef memory operatorAccount = _account("operator");

        // 5. The notice period is over: the identity is refused.
        _step(swarm, "operator", ids.bindingB, "join", "swarm", s, _none(), Disposition.REFUSE, R_DENY_MATCH);
        // 6. The account behind it is another object, and no extension was adopted.
        _step(swarm, "operator", ids.bindingB, "join", "swarm", operatorAccount, _none(), Disposition.PROCEED, R_DEFAULT);

        // 7. The group adopts the extension: its binding now names the derived list as well.
        BindingConfig memory c = _binding(scope, _action("join"), _doc("case_b_binding_extended_json"));
        c.deny = new ListRef[](2);
        c.deny[0] = ListRef(address(registry), ids.barred, bytes32(0));
        c.deny[1] = ListRef(address(registry), ids.barredAnchors, bytes32(0));
        c.denyThreshold = 1;
        c.onNoMatch = Outcome.ALLOW;
        vm.startBroadcast(deployerPk);
        guard.amend(ids.bindingB, c, _uri("case-b/binding-extended.json"));
        vm.stopBroadcast();
        _step(swarm, "operator", ids.bindingB, "join", "swarm", operatorAccount, _none(), Disposition.REFUSE, R_DENY_MATCH);

        // 8. The operator retires its anchor and names an uninvolved account as successor.
        vm.startBroadcast(_pk("operator"));
        anchors.retire(_addr("carol"));
        vm.stopBroadcast();
        _step(swarm, "carol", ids.bindingB, "join", "swarm", _account("carol"), _none(), Disposition.PROCEED, R_DEFAULT);

        // 9. Another account takes the identity over and binds itself to it: related by its own act.
        vm.startBroadcast(_pk("operator"));
        identities.transferFrom(_addr("operator"), _addr("bob"), ids.agentS);
        vm.stopBroadcast();
        vm.startBroadcast(_pk("bob"));
        anchors.bind(address(identities), ids.agentS);
        vm.stopBroadcast();
        _step(swarm, "bob", ids.bindingB, "join", "swarm", _account("bob"), _none(), Disposition.REFUSE, R_DENY_MATCH);

        // 10. The objection is upheld and the entry revoked: the derived refusal goes with it.
        vm.startBroadcast(_pk("manager"));
        registry.revokeEntry(ids.barred, _key(s), "OBJECTION_UPHELD");
        vm.stopBroadcast();
        _step(swarm, "bob", ids.bindingB, "join", "swarm", _account("bob"), _none(), Disposition.PROCEED, R_DEFAULT);
    }

    // ---------------------------------------------------------------- Case C

    function caseC() external {
        _init(true);
        Scope memory scope = Scope(address(service), _ctx("service"), _doc("case_c_scope_json"));
        SubjectRef memory alice = _account("alice");
        SubjectRef memory bob = _account("bob");
        SubjectRef memory excluded = SubjectRef(KIND_DIGEST, 0, address(0), vm.parseJsonBytes32(plan, ".tools.excluded"));
        SubjectRef memory current = SubjectRef(KIND_DIGEST, 0, address(0), vm.parseJsonBytes32(plan, ".tools.current"));

        vm.startBroadcast(deployerPk);
        bytes32 scopeId = registry.declareScope(scope, _uri("case-c/scope.json"));
        vm.stopBroadcast();

        EntryInput memory designation;
        designation.reason = "DESIGNATED";
        vm.startBroadcast(_pk("manager"));
        ids.partners = registry.createList(_listConfig(Polarity.ALLOW, Mode.ENUMERATED, scopeId, 4), _uri("case-c/list-partners.json"));
        ids.barredC = registry.createList(_listConfig(Polarity.DENY, Mode.ENUMERATED, scopeId, 5), _uri("case-c/list-barred.json"));
        ids.sanctioned =
            registry.createList(_listConfig(Polarity.DENY, Mode.COMMITTED, scopeId, 6), _uri("case-c/list-sanctioned.json"));
        ids.excludedTools = registry.createList(
            _listConfig(Polarity.DENY, Mode.ENUMERATED, scopeId, 7), _uri("case-c/list-excluded-tools.json")
        );
        registry.addEntry(ids.partners, alice, designation, "");
        registry.addEntry(ids.partners, bob, designation, "");
        registry.addEntry(ids.barredC, bob, designation, "");
        registry.commitSet(
            ids.sanctioned,
            vm.parseJsonBytes32(plan, ".set.root"),
            SetKind.SORTED,
            uint64(vm.parseJsonUint(plan, ".set.size")),
            ""
        );
        registry.addEntry(ids.excludedTools, excluded, designation, "");
        vm.stopBroadcast();

        BindingConfig memory c = _binding(scope, _action("invoke"), _doc("case_c_binding_json"));
        c.allow = _refs(ids.partners);
        c.allowThreshold = 1;
        c.deny = new ListRef[](2);
        c.deny[0] = ListRef(address(registry), ids.barredC, bytes32(0));
        c.deny[1] = ListRef(address(registry), ids.sanctioned, bytes32(0));
        c.denyThreshold = 1;
        BindingConfig memory t = _binding(scope, _action("use_tool"), _doc("case_c_binding_tools_json"));
        t.role = Role.OBJECT;
        t.deny = _refs(ids.excludedTools);
        t.denyThreshold = 1;
        t.onNoMatch = Outcome.ALLOW;
        t.onIndeterminate = Disposition.REFUSE;
        vm.startBroadcast(deployerPk);
        ids.bindingC = guard.adopt(c, bytes32(0), _uri("case-c/binding.json"));
        ids.bindingTools = guard.adopt(t, bytes32(uint256(1)), _uri("case-c/binding-tools.json"));
        vm.stopBroadcast();

        bytes memory proofAlice = vm.parseJsonBytes(plan, ".set.proofAlice");
        // 1. On the allow list, not on the deny list, absent from the committed set: allowed.
        _step(service, "alice", ids.bindingC, "invoke", "service", alice, _third(proofAlice), Disposition.PROCEED, R_ALLOW_MATCH);
        // 2. Without the proof of absence the deny side is open: not a pass, deferred.
        _step(service, "alice", ids.bindingC, "invoke", "service", alice, _none(), Disposition.DEFER, R_UNDETERMINED_INPUT);
        // 3. On both lists: the conflict is decided as the binding declares.
        _step(
            service, "bob", ids.bindingC, "invoke", "service", bob, _third(vm.parseJsonBytes(plan, ".set.proofBob")), Disposition.REFUSE, R_CONFLICT
        );
        // 4. On no list: refused by default, and put on no deny list.
        _step(
            service,
            "carol",
            ids.bindingC,
            "invoke",
            "service",
            _account("carol"),
            _third(vm.parseJsonBytes(plan, ".set.proofCarol")),
            Disposition.REFUSE,
            R_DEFAULT
        );
        // 5. Somebody else names the allowed account and presents its proof.
        _step(
            service, "mallory", ids.bindingC, "invoke", "service", alice, _third(proofAlice), Disposition.REFUSE, R_PRESENTER_NOT_AUTHORIZED
        );
        // 6. The same service refuses an excluded tool version and runs the current one.
        _step(service, "alice", ids.bindingTools, "use_tool", "service", excluded, _none(), Disposition.REFUSE, R_DENY_MATCH);
        _step(service, "alice", ids.bindingTools, "use_tool", "service", current, _none(), Disposition.PROCEED, R_DEFAULT);

        // 7. The result of step 1 as it would be kept by whoever relies on it.
        Assessment memory earlier =
            guard.assess(ids.bindingC, alice, _addr("alice"), _action("invoke"), _ctx("service"), _third(proofAlice));
        require(earlier.outcome == Outcome.ALLOW, "case C: earlier assessment");
        ids.earlierDigest = earlier.stateDigest;
        ids.earlierValidUntil = earlier.validUntil;

        // 8. The account leaves the allow list. The same request with the same proof is refused.
        vm.startBroadcast(_pk("manager"));
        registry.revokeEntry(ids.partners, _key(alice), "WITHDRAWN");
        vm.stopBroadcast();
        _step(service, "alice", ids.bindingC, "invoke", "service", alice, _third(proofAlice), Disposition.REFUSE, R_DEFAULT);

        // 9. A new set is committed that contains the account. Proofs against the earlier root are void.
        vm.startBroadcast(_pk("manager"));
        registry.commitSet(
            ids.sanctioned,
            vm.parseJsonBytes32(plan, ".set.grownRoot"),
            SetKind.SORTED,
            uint64(vm.parseJsonUint(plan, ".set.grownSize")),
            ""
        );
        vm.stopBroadcast();

        _save();
    }

    // ---------------------------------------------------------------- report

    function report() external {
        _init(true);
        Request memory none;
        SubjectRef memory agentA = _entry(ids.agentA);
        SubjectRef memory agentB = _entry(ids.agentB);
        SubjectRef memory agentS = _entry(ids.agentS);
        SubjectRef memory alice = _account("alice");
        bytes32 bid = _action("bid");
        bytes32 join = _action("join");
        bytes32 invoke = _action("invoke");
        bytes32 useTool = _action("use_tool");

        // Case A: 2 bids recorded, 5 refused.
        require(_count(board, "task", bid, agentA, 1, 3), "case A: identity A");
        require(_count(board, "task", bid, agentB, 1, 2), "case A: identity B");
        Assessment memory a =
            guard.assess(ids.bindingA, agentB, _addr("bob"), bid, _ctx("task"), _one(_history(21, 22)));
        require(a.outcome == Outcome.DENY && a.findings[0].reason == "CREDENTIAL_NOT_VALID", "case A: expiry");
        a = guard.assess(ids.bindingA, agentA, _addr("carol"), bid, _ctx("task"), _one(_history(11, 12)));
        require(a.standing == Match.MATCH && a.controller == _addr("carol"), "case A: standing of the new controller");
        require(a.outcome == Outcome.DENY && a.findings[0].reason == "CREDENTIAL_NOT_VALID", "case A: change of controller");

        // Case B: 5 admissions, 3 refusals; the entry is revoked and nothing is derived from it any more.
        require(_count(swarm, "swarm", join, agentS, 2, 1), "case B: identity");
        require(_count(swarm, "swarm", join, _account("operator"), 1, 1), "case B: operator account");
        require(_count(swarm, "swarm", join, _account("carol"), 1, 0), "case B: named successor");
        require(_count(swarm, "swarm", join, _account("bob"), 1, 1), "case B: new anchor");
        Entry memory entry = registry.entryOf(ids.barred, _key(agentS));
        require(entry.status == EntryStatus.REVOKED && entry.basis == Basis.EVIDENCED, "case B: entry");
        require(entry.validFrom == entry.listedAt + vm.parseJsonUint(plan, ".parameters.noticePeriod"), "case B: notice");
        Finding memory f = registry.matchOf(ids.barredAnchors, _account("bob"), none, "");
        require(f.result == Match.NO_MATCH && f.reason == R_NOT_RELATED, "case B: derived result follows the origin");
        f = registry.matchOf(ids.barredAnchors, _account("carol"), none, "");
        require(f.result == Match.NO_MATCH && f.reason == R_NOT_RELATED, "case B: naming a successor relates nobody");
        (BindingInfo memory infoB,) = guard.bindingOf(ids.bindingB);
        require(infoB.version == 2, "case B: binding version");

        // Case C: 1 call served, 5 not served; 1 tool use refused, 1 carried out.
        require(_count(service, "service", invoke, alice, 1, 3), "case C: alice");
        require(_count(service, "service", invoke, _account("bob"), 0, 1), "case C: bob");
        require(_count(service, "service", invoke, _account("carol"), 0, 1), "case C: carol");
        require(
            _count(service, "service", useTool, SubjectRef(KIND_DIGEST, 0, address(0), vm.parseJsonBytes32(plan, ".tools.excluded")), 0, 1),
            "case C: excluded tool"
        );
        require(
            _count(service, "service", useTool, SubjectRef(KIND_DIGEST, 0, address(0), vm.parseJsonBytes32(plan, ".tools.current")), 1, 0),
            "case C: current tool"
        );
        // The earlier result is no ground to act on any more.
        bool earlierCurrent = guard.isCurrent(ids.bindingC, ids.earlierDigest, uint64(ids.earlierValidUntil));
        require(!earlierCurrent, "case C: earlier assessment still current");
        // The earlier proof shows nothing against the new root; membership can be shown.
        f = registry.matchOf(ids.sanctioned, alice, none, vm.parseJsonBytes(plan, ".set.proofAlice"));
        require(f.result == Match.UNDETERMINED && f.reason == R_PROOF_INVALID, "case C: earlier proof");
        f = registry.matchOf(ids.sanctioned, alice, none, vm.parseJsonBytes(plan, ".set.grownMemberProofAlice"));
        require(f.result == Match.MATCH && f.reason == R_SET_MEMBER, "case C: membership in the new set");

        _write(earlierCurrent);
    }

    function _write(bool earlierCurrent) internal {
        string memory c = "contracts";
        vm.serializeAddress(c, "registry", address(registry));
        vm.serializeAddress(c, "guard", address(guard));
        vm.serializeAddress(c, "credentialHistoryEvaluator", address(evaluator));
        vm.serializeAddress(c, "boundAnchorRelation", address(relation));
        vm.serializeAddress(c, "taskBoard", address(board));
        vm.serializeAddress(c, "swarmMembership", address(swarm));
        vm.serializeAddress(c, "inferenceGateway", address(service));
        vm.serializeAddress(c, "identityFixture", address(identities));
        vm.serializeAddress(c, "assertionFixture", address(assertions));
        vm.serializeAddress(c, "taskLedgerFixture", address(ledger));
        string memory contractsJson = vm.serializeAddress(c, "anchorRegistry", address(anchors));

        string memory a = "caseA";
        vm.serializeBytes32(a, "list", ids.qualified);
        vm.serializeBytes32(a, "binding", ids.bindingA);
        vm.serializeBytes32(a, "criteria", registry.listOf(ids.qualified).criteriaId);
        vm.serializeUint(a, "identityA", ids.agentA);
        vm.serializeUint(a, "identityB", ids.agentB);
        vm.serializeUint(a, "bidsRecorded", 2);
        string memory aJson = vm.serializeUint(a, "bidsRefused", 5);

        string memory b = "caseB";
        vm.serializeBytes32(b, "list", ids.barred);
        vm.serializeBytes32(b, "derivedList", ids.barredAnchors);
        vm.serializeBytes32(b, "binding", ids.bindingB);
        vm.serializeUint(b, "bindingVersion", 2);
        vm.serializeUint(b, "identity", ids.agentS);
        Entry memory entry = registry.entryOf(ids.barred, _key(_entry(ids.agentS)));
        vm.serializeUint(b, "entryListedAt", entry.listedAt);
        vm.serializeUint(b, "entryValidFrom", entry.validFrom);
        vm.serializeBytes32(b, "entryBasisHash", entry.basisHash);
        vm.serializeUint(b, "joinsAdmitted", 5);
        string memory bJson = vm.serializeUint(b, "joinsRefused", 3);

        string memory k = "caseC";
        vm.serializeBytes32(k, "allowList", ids.partners);
        vm.serializeBytes32(k, "denyList", ids.barredC);
        vm.serializeBytes32(k, "committedDenyList", ids.sanctioned);
        vm.serializeBytes32(k, "toolList", ids.excludedTools);
        vm.serializeBytes32(k, "binding", ids.bindingC);
        vm.serializeBytes32(k, "toolBinding", ids.bindingTools);
        vm.serializeBytes32(k, "committedRoot", registry.listOf(ids.sanctioned).setRoot);
        vm.serializeBytes32(k, "earlierStateDigest", ids.earlierDigest);
        vm.serializeBytes32(k, "currentStateDigest", guard.stateDigestOf(ids.bindingC));
        vm.serializeBool(k, "earlierAssessmentCurrent", earlierCurrent);
        vm.serializeUint(k, "callsServed", 1);
        vm.serializeUint(k, "callsNotServed", 5);
        vm.serializeUint(k, "toolUsesRefused", 1);
        string memory kJson = vm.serializeUint(k, "toolUsesCarriedOut", 1);

        string memory root = "evidence";
        vm.serializeString(root, "network", network);
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "readAtBlock", block.number);
        vm.serializeAddress(root, "deployer", vm.addr(deployerPk));
        vm.serializeString(root, "contracts", contractsJson);
        vm.serializeString(root, "caseA", aJson);
        vm.serializeString(root, "caseB", bJson);
        string memory out = vm.serializeString(root, "caseC", kJson);
        vm.writeJson(out, string.concat(dir, "evidence.json"));
        console2.log("all checks passed; wrote", string.concat(dir, "evidence.json"));
    }

    // ---------------------------------------------------------------- helpers

    /// @dev One gated action, sent by `actor`. The result computed here, before anything is sent,
    /// has to be the one the specification gives.
    function _step(
        AWFExampleConsumer consumer,
        string memory actor,
        bytes32 bindingId,
        string memory action,
        string memory context,
        SubjectRef memory subject,
        bytes[] memory evidence,
        Disposition expected,
        bytes32 expectedReason
    ) internal {
        vm.startBroadcast(_pk(actor));
        (Disposition d,, bytes32 reason) = consumer.act(bindingId, _action(action), _ctx(context), subject, evidence);
        vm.stopBroadcast();
        require(d == expected && reason == expectedReason, string.concat("unexpected result for ", actor, " / ", action));
    }

    function _count(
        AWFExampleConsumer consumer,
        string memory context,
        bytes32 action,
        SubjectRef memory subject,
        uint256 done,
        uint256 refused
    ) internal view returns (bool) {
        bytes32 key = _key(subject);
        return consumer.done(_ctx(context), action, key) == done && consumer.refused(_ctx(context), action, key) == refused;
    }

    function _init(bool loadState) internal {
        network = vm.envString("NETWORK");
        deployerPk = vm.envUint("DEPLOYER_PK");
        dir = string.concat("deployments/", network, "/");
        plan = vm.readFile(string.concat(dir, "plan.json"));
        require(vm.parseJsonUint(plan, ".chainId") == block.chainid, "plan is for another chain");
        require(vm.parseJsonAddress(plan, ".deployer") == vm.addr(deployerPk), "plan is for another deployer key");
        require(_addr("manager") == vm.addr(_pk("manager")), "plan accounts do not match the key");

        if (loadState) {
            string memory s = vm.readFile(string.concat(dir, "state.json"));
            registry = AWFRegistry(vm.parseJsonAddress(s, ".registry"));
            guard = AWFGuard(vm.parseJsonAddress(s, ".guard"));
            identities = IdentityFixture(vm.parseJsonAddress(s, ".identities"));
            assertions = AssertionFixture(vm.parseJsonAddress(s, ".assertions"));
            ledger = TaskLedgerFixture(vm.parseJsonAddress(s, ".ledger"));
            anchors = AIDRegistry(vm.parseJsonAddress(s, ".anchors"));
            evaluator = AWFCredentialHistoryEvaluator(vm.parseJsonAddress(s, ".evaluator"));
            relation = AWFBoundAnchorRelation(vm.parseJsonAddress(s, ".relation"));
            board = AWFExampleConsumer(vm.parseJsonAddress(s, ".board"));
            swarm = AWFExampleConsumer(vm.parseJsonAddress(s, ".swarm"));
            service = AWFExampleConsumer(vm.parseJsonAddress(s, ".service"));
            ids.agentA = vm.parseJsonUint(s, ".agentA");
            ids.agentB = vm.parseJsonUint(s, ".agentB");
            ids.agentS = vm.parseJsonUint(s, ".agentS");
            ids.qualified = vm.parseJsonBytes32(s, ".qualified");
            ids.bindingA = vm.parseJsonBytes32(s, ".bindingA");
            ids.barred = vm.parseJsonBytes32(s, ".barred");
            ids.barredAnchors = vm.parseJsonBytes32(s, ".barredAnchors");
            ids.bindingB = vm.parseJsonBytes32(s, ".bindingB");
            ids.partners = vm.parseJsonBytes32(s, ".partners");
            ids.barredC = vm.parseJsonBytes32(s, ".barredC");
            ids.sanctioned = vm.parseJsonBytes32(s, ".sanctioned");
            ids.excludedTools = vm.parseJsonBytes32(s, ".excludedTools");
            ids.bindingC = vm.parseJsonBytes32(s, ".bindingC");
            ids.bindingTools = vm.parseJsonBytes32(s, ".bindingTools");
            ids.earlierDigest = vm.parseJsonBytes32(s, ".earlierDigest");
            ids.earlierValidUntil = vm.parseJsonUint(s, ".earlierValidUntil");
            require(address(registry).code.length != 0 && address(guard).code.length != 0, "state.json is from another run");
        }
    }

    function _save() internal {
        string memory s = "state";
        vm.serializeAddress(s, "registry", address(registry));
        vm.serializeAddress(s, "guard", address(guard));
        vm.serializeAddress(s, "identities", address(identities));
        vm.serializeAddress(s, "assertions", address(assertions));
        vm.serializeAddress(s, "ledger", address(ledger));
        vm.serializeAddress(s, "anchors", address(anchors));
        vm.serializeAddress(s, "evaluator", address(evaluator));
        vm.serializeAddress(s, "relation", address(relation));
        vm.serializeAddress(s, "board", address(board));
        vm.serializeAddress(s, "swarm", address(swarm));
        vm.serializeAddress(s, "service", address(service));
        vm.serializeUint(s, "agentA", ids.agentA);
        vm.serializeUint(s, "agentB", ids.agentB);
        vm.serializeUint(s, "agentS", ids.agentS);
        vm.serializeBytes32(s, "qualified", ids.qualified);
        vm.serializeBytes32(s, "bindingA", ids.bindingA);
        vm.serializeBytes32(s, "barred", ids.barred);
        vm.serializeBytes32(s, "barredAnchors", ids.barredAnchors);
        vm.serializeBytes32(s, "bindingB", ids.bindingB);
        vm.serializeBytes32(s, "partners", ids.partners);
        vm.serializeBytes32(s, "barredC", ids.barredC);
        vm.serializeBytes32(s, "sanctioned", ids.sanctioned);
        vm.serializeBytes32(s, "excludedTools", ids.excludedTools);
        vm.serializeBytes32(s, "bindingC", ids.bindingC);
        vm.serializeBytes32(s, "bindingTools", ids.bindingTools);
        vm.serializeBytes32(s, "earlierDigest", ids.earlierDigest);
        string memory out = vm.serializeUint(s, "earlierValidUntil", ids.earlierValidUntil);
        vm.writeJson(out, string.concat(dir, "state.json"));
    }

    function _pk(string memory label) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(deployerPk, label)));
    }

    function _addr(string memory label) internal view returns (address) {
        return vm.parseJsonAddress(plan, string.concat(".actors.", label));
    }

    function _fund(string memory label, uint256 amount) internal {
        (bool ok,) = payable(_addr(label)).call{value: amount}("");
        require(ok, "funding failed");
    }

    function _doc(string memory name) internal view returns (bytes32) {
        return vm.parseJsonBytes32(plan, string.concat(".documents.", name));
    }

    function _uri(string memory file) internal view returns (string memory) {
        return string.concat(vm.parseJsonString(plan, ".recordBase"), file);
    }

    function _ctx(string memory name) internal view returns (bytes32) {
        return vm.parseJsonBytes32(plan, string.concat(".contexts.", name));
    }

    function _action(string memory name) internal view returns (bytes32) {
        return vm.parseJsonBytes32(plan, string.concat(".actions.", name));
    }

    function _account(string memory label) internal view returns (SubjectRef memory) {
        return SubjectRef(KIND_ACCOUNT, block.chainid, address(0), bytes32(uint256(uint160(_addr(label)))));
    }

    function _entry(uint256 id) internal view returns (SubjectRef memory) {
        return SubjectRef(KIND_ENTRY, block.chainid, address(identities), bytes32(id));
    }

    function _key(SubjectRef memory s) internal pure returns (bytes32) {
        return keccak256(abi.encode(s.kind, s.chainId, s.namespace, s.id));
    }

    function _credentialSubject(uint256 agentId) internal view returns (IAssertionSource.Subject memory) {
        return IAssertionSource.Subject(keccak256("erc8004"), abi.encode(block.chainid, address(identities), agentId));
    }

    function _history(uint256 first, uint256 second) internal pure returns (bytes memory) {
        AWFCredentialHistoryEvaluator.TaskRef[] memory refs = new AWFCredentialHistoryEvaluator.TaskRef[](2);
        refs[0] = AWFCredentialHistoryEvaluator.TaskRef(first, 1);
        refs[1] = AWFCredentialHistoryEvaluator.TaskRef(second, 1);
        return abi.encode(refs);
    }

    function _listConfig(Polarity polarity, Mode mode, bytes32 scopeId, uint256 salt) internal pure returns (ListConfig memory c) {
        c.polarity = polarity;
        c.mode = mode;
        c.scopeId = scopeId;
        c.salt = bytes32(salt);
    }

    /// @dev A binding for one action with the rules most cases share: actor role, deny wins a
    /// conflict, no match is refused, the undetermined is deferred.
    function _binding(Scope memory scope, bytes32 action, bytes32 documentHash) internal pure returns (BindingConfig memory c) {
        c.scope = scope;
        c.role = Role.ACTOR;
        c.actions = new ActionRule[](1);
        c.actions[0] = ActionRule(action, false);
        c.onConflict = Outcome.DENY;
        c.onNoMatch = Outcome.DENY;
        c.onIndeterminate = Disposition.DEFER;
        c.onNotApplicable = Disposition.PROCEED;
        c.documentHash = documentHash;
    }

    function _refs(bytes32 listId) internal view returns (ListRef[] memory refs) {
        refs = new ListRef[](1);
        refs[0] = ListRef(address(registry), listId, bytes32(0));
    }

    function _none() internal pure returns (bytes[] memory) {
        return new bytes[](0);
    }

    function _one(bytes memory first) internal pure returns (bytes[] memory e) {
        e = new bytes[](1);
        e[0] = first;
    }

    /// @dev Evidence for the third list of a binding (the committed deny set of Case C).
    function _third(bytes memory proof) internal pure returns (bytes[] memory e) {
        e = new bytes[](3);
        e[2] = proof;
    }
}
