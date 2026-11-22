// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AAFBase.sol";
import {IERC165} from "../assets/erc-8507/contracts/Introspection.sol";

contract AAFRegistryTest is AAFBase {
    ScriptedEvaluator internal evaluator;

    function setUp() public override {
        super.setUp();
        evaluator = new ScriptedEvaluator();
    }

    // ------------------------------------------------------------ identifiers

    function test_identifiers_followTheirFormulas() public view {
        SubjectRef memory s = _entry(address(identities), 7);
        assertEq(registry.subjectKeyOf(s), keccak256(abi.encode(KIND_ENTRY, block.chainid, address(identities), bytes32(uint256(7)))));

        Scope memory scope = Scope(address(venue), CONTEXT, keccak256("doc"));
        assertEq(
            registry.scopeIdOf(scope),
            keccak256(abi.encode(SCOPE_TAG, block.chainid, address(venue), CONTEXT, keccak256("doc")))
        );

        Criteria memory c = Criteria(keccak256("doc"), address(evaluator), bytes32("code"), bytes32("config"), bytes32("rule"), 0);
        assertEq(
            registry.criteriaIdOf(c),
            keccak256(
                abi.encode(
                    CRITERIA_TAG, block.chainid, keccak256("doc"), address(evaluator), bytes32("code"), bytes32("config"), bytes32("rule"), uint8(0)
                )
            )
        );

        ListConfig memory l;
        l.polarity = Polarity.DENY;
        l.mode = Mode.ENUMERATED;
        l.salt = bytes32(uint256(9));
        assertEq(
            registry.listIdOf(manager, l),
            keccak256(
                abi.encode(
                    LIST_TAG, block.chainid, address(registry), manager, Polarity.DENY, Mode.ENUMERATED, bytes32(0), bytes32(uint256(9))
                )
            )
        );
    }

    function test_subjectKinds_areDistinctObjects() public view {
        // The same number under another kind, chain or namespace is another object.
        bytes32 a = _key(SubjectRef(KIND_ACCOUNT, block.chainid, address(0), bytes32(uint256(1))));
        bytes32 b = _key(SubjectRef(KIND_ENTRY, block.chainid, address(0), bytes32(uint256(1))));
        bytes32 c = _key(SubjectRef(KIND_ACCOUNT, block.chainid + 1, address(0), bytes32(uint256(1))));
        bytes32 d = _key(SubjectRef(KIND_ENTRY, block.chainid, address(identities), bytes32(uint256(1))));
        assertTrue(a != b && a != c && b != d && c != d);
    }

    function test_supportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IAAFRegistry).interfaceId));
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
        assertFalse(registry.supportsInterface(0xffffffff));
    }

    // ------------------------------------------------------------ scopes and criteria

    function test_declareScope_recordsAndGivesNoRight() public {
        Scope memory scope = Scope(address(venue), CONTEXT, keccak256("doc"));
        bytes32 id = registry.scopeIdOf(scope);
        vm.expectEmit();
        emit IAAFRegistry.ScopeDeclared(id, address(venue), CONTEXT, keccak256("doc"), "ipfs://scope", mallory);
        vm.prank(mallory);
        assertEq(registry.declareScope(scope, "ipfs://scope"), id);
        assertEq(registry.scopeOf(id).anchor, address(venue));
        // Declaring a scope for somebody else's contract does not let the declarer bind it.
        BindingConfig memory c = _config(_one(_list(Polarity.ALLOW)), _none());
        vm.prank(mallory);
        vm.expectRevert(IAAFGuard.NotAuthorized.selector);
        guard.adopt(c, bytes32(0), "");
    }

    function test_registerCriteria_pinsCodeAndConfiguration() public {
        bytes32 id = registry.registerCriteria(keccak256("doc"), address(evaluator), bytes32("rule"), 0, "ipfs://criteria");
        Criteria memory c = registry.criteriaOf(id);
        assertEq(c.moduleCodeHash, address(evaluator).codehash);
        assertEq(c.moduleConfig, evaluator.configHash());
        assertEq(registry.criteriaIdOf(c), id);
        // The same input after a configuration change is another version.
        evaluator.setConfig(keccak256("config/2"));
        assertTrue(registry.registerCriteria(keccak256("doc"), address(evaluator), bytes32("rule"), 0, "") != id);
    }

    function test_registerCriteria_refusesWhatCannotBePinned() public {
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.registerCriteria(keccak256("doc"), alice, bytes32(0), 0, ""); // no code
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.registerCriteria(keccak256("doc"), address(identities), bytes32(0), 0, ""); // no configHash
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.registerCriteria(keccak256("doc"), address(0), bytes32("rule"), 0, ""); // rule without module
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.registerCriteria(keccak256("doc"), address(evaluator), bytes32(0), 9, ""); // fan-out above the bound
    }

    function test_criteriaWithoutModule_describeAnEnumeratedList() public {
        bytes32 id = registry.registerCriteria(keccak256("doc"), address(0), bytes32(0), 0, "");
        ListConfig memory c = _listConfig(Polarity.ALLOW, Mode.ENUMERATED);
        c.criteriaId = id;
        vm.prank(manager);
        bytes32 listId = registry.createList(c, "");
        assertEq(registry.listOf(listId).criteriaId, id);
    }

    // ------------------------------------------------------------ lists

    function test_createList_setsWhatNeverChanges() public {
        ListConfig memory c = _listConfig(Polarity.DENY, Mode.ENUMERATED);
        c.scopeId = keccak256("scope");
        c.noticePeriod = 3600;
        bytes32 id = registry.listIdOf(manager, c);
        vm.expectEmit();
        emit IAAFRegistry.ListCreated(id, manager, Polarity.DENY, Mode.ENUMERATED, keccak256("scope"), bytes32(0), 3600, "ipfs://list");
        vm.prank(manager);
        assertEq(registry.createList(c, "ipfs://list"), id);
        ListInfo memory l = registry.listOf(id);
        assertEq(l.manager, manager);
        assertEq(uint8(l.polarity), uint8(Polarity.DENY));
        assertEq(uint8(l.mode), uint8(Mode.ENUMERATED));
        assertEq(l.revision, 1);
        assertEq(l.noticePeriod, 3600);

        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.ListExists.selector);
        registry.createList(c, "");
    }

    function test_createList_polarityIsPartOfTheIdentifier() public {
        ListConfig memory c = _listConfig(Polarity.ALLOW, Mode.ENUMERATED);
        bytes32 allowId = registry.listIdOf(manager, c);
        c.polarity = Polarity.DENY;
        assertTrue(registry.listIdOf(manager, c) != allowId);
    }

    function test_createList_refusesIncoherentConfigurations() public {
        ListConfig memory c = _listConfig(Polarity.NONE, Mode.ENUMERATED);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");

        c = _listConfig(Polarity.ALLOW, Mode.NONE);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");

        c = _listConfig(Polarity.ALLOW, Mode.PREDICATE); // a predicate list needs an evaluator
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");

        c = _listConfig(Polarity.ALLOW, Mode.ENUMERATED);
        c.criteriaId = keccak256("unregistered");
        vm.expectRevert(IAAFRegistry.UnknownCriteria.selector);
        registry.createList(c, "");

        c.criteriaId = registry.registerCriteria(keccak256("doc"), address(evaluator), bytes32(0), 0, "");
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector); // an enumerated list has no evaluator
        registry.createList(c, "");

        c = _listConfig(Polarity.ALLOW, Mode.ENUMERATED);
        c.source = keccak256("source"); // only a derived list has a source
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");

        c = _listConfig(Polarity.ALLOW, Mode.COMMITTED);
        c.noticePeriod = 1; // notice applies to entries
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.createList(c, "");
    }

    function test_unknownList_isUndetermined() public view {
        Finding memory f = _match(keccak256("no such list"), _account(alice));
        _expect(f, Match.UNDETERMINED, R_LIST_UNKNOWN);
        (uint64 revision, bytes32 state) = registry.stateOf(keccak256("no such list"));
        assertEq(revision, 0);
        assertEq(state, bytes32(0));
    }

    // ------------------------------------------------------------ entries

    function test_entry_listedSubjectMatches() public {
        bytes32 list = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        _expect(_match(list, s), Match.NO_MATCH, R_NOT_LISTED);

        EntryInput memory input = _input();
        vm.expectEmit();
        emit IAAFRegistry.EntryAdded(
            list, _key(s), s, 1, uint64(T0), 0, Basis.DESIGNATION, bytes32(0), "TEST", address(0), bytes32(0), "ipfs://basis"
        );
        vm.prank(manager);
        registry.addEntry(list, s, input, "ipfs://basis");

        Finding memory f = _match(list, s);
        _expect(f, Match.MATCH, R_LISTED);
        assertEq(uint8(f.polarity), uint8(Polarity.ALLOW));
        assertEq(f.revision, 2);
        assertEq(f.validUntil, type(uint64).max);
        (Match m, bytes32 reason) = registry.check(list, s);
        assertEq(m, Match.MATCH);
        assertEq(reason, R_LISTED);
        _expect(_match(list, _account(bob)), Match.NO_MATCH, R_NOT_LISTED);
    }

    function test_entry_onlyTheManagerWrites() public {
        bytes32 list = _list(Polarity.DENY);
        vm.prank(mallory);
        vm.expectRevert(IAAFRegistry.NotManager.selector);
        registry.addEntry(list, _account(alice), _input(), "");
        vm.expectRevert(IAAFRegistry.UnknownList.selector);
        registry.addEntry(keccak256("x"), _account(alice), _input(), "");
    }

    function test_entry_designationNeedsNoEvidence_factDoes() public {
        bytes32 list = _list(Polarity.DENY);
        // "I do not work with this account" stands on the manager's authority alone.
        _add(list, _account(alice));
        // "This account did X" is a statement of fact and commits to its evidence.
        EntryInput memory input = _input();
        input.basis = Basis.EVIDENCED;
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.BasisRequired.selector);
        registry.addEntry(list, _account(bob), input, "");
        input.basisHash = keccak256("evidence bundle");
        vm.prank(manager);
        registry.addEntry(list, _account(bob), input, "ipfs://evidence");
        assertEq(registry.entryOf(list, _key(_account(bob))).basisHash, keccak256("evidence bundle"));
        assertEq(_match(list, _account(bob)).basis, keccak256("evidence bundle"));
    }

    function test_entry_window_pendingActiveExpired() public {
        bytes32 list = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        EntryInput memory input = _input();
        input.validFrom = uint64(T0 + 100);
        input.validUntil = uint64(T0 + 200);
        vm.prank(manager);
        registry.addEntry(list, s, input, "");

        Finding memory f = _match(list, s);
        _expect(f, Match.NO_MATCH, R_ENTRY_PENDING);
        assertEq(f.validUntil, T0 + 99); // the answer changes when the entry takes effect

        vm.warp(T0 + 100);
        f = _match(list, s);
        _expect(f, Match.MATCH, R_LISTED);
        assertEq(f.validUntil, T0 + 199);

        vm.warp(T0 + 200);
        _expect(_match(list, s), Match.NO_MATCH, R_ENTRY_EXPIRED);

        // An expired entry may be replaced; the serial counts the entries the subject has had.
        _add(list, s);
        assertEq(registry.entryOf(list, _key(s)).serial, 2);
        _expect(_match(list, s), Match.MATCH, R_LISTED);
    }

    function test_entry_invalidWindows() public {
        bytes32 list = _list(Polarity.ALLOW);
        EntryInput memory input = _input();
        input.validFrom = uint64(T0 - 1);
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidWindow.selector);
        registry.addEntry(list, _account(alice), input, "");
        input.validFrom = uint64(T0 + 10);
        input.validUntil = uint64(T0 + 10);
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidWindow.selector);
        registry.addEntry(list, _account(alice), input, "");
    }

    function test_entry_oneLiveEntryPerSubject() public {
        bytes32 list = _list(Polarity.ALLOW);
        _add(list, _account(alice));
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.EntryExists.selector);
        registry.addEntry(list, _account(alice), _input(), "");
    }

    function test_entry_suspendResumeRevoke() public {
        bytes32 list = _list(Polarity.DENY);
        SubjectRef memory s = _account(alice);
        bytes32 key = _add(list, s);

        vm.expectEmit();
        emit IAAFRegistry.EntryStatusChanged(list, key, 1, EntryStatus.SUSPENDED, "REVIEW");
        vm.prank(manager);
        registry.suspendEntry(list, key, "REVIEW");
        _expect(_match(list, s), Match.NO_MATCH, R_ENTRY_SUSPENDED);
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.EntryExists.selector); // suspended is still an entry
        registry.addEntry(list, s, _input(), "");

        vm.prank(manager);
        registry.resumeEntry(list, key, "REVIEWED");
        _expect(_match(list, s), Match.MATCH, R_LISTED);

        vm.prank(manager);
        registry.revokeEntry(list, key, "WITHDRAWN");
        _expect(_match(list, s), Match.NO_MATCH, R_ENTRY_REVOKED);
        Entry memory e = registry.entryOf(list, key);
        assertEq(uint8(e.status), uint8(EntryStatus.REVOKED)); // the record of the entry stays
        assertEq(e.listedAt, T0);

        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.EntryNotFound.selector);
        registry.revokeEntry(list, key, "AGAIN");
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.EntryNotFound.selector);
        registry.resumeEntry(list, key, "AGAIN");

        _add(list, s);
        assertEq(registry.entryOf(list, key).serial, 2);
    }

    function test_entry_leavingOneListIsNotJoiningTheOther() public {
        bytes32 allow = _list(Polarity.ALLOW);
        bytes32 deny = _list(Polarity.DENY);
        SubjectRef memory s = _account(alice);
        _add(deny, s);
        _revoke(deny, s);
        _expect(_match(deny, s), Match.NO_MATCH, R_ENTRY_REVOKED);
        _expect(_match(allow, s), Match.NO_MATCH, R_NOT_LISTED);
    }

    function test_noticePeriod_delaysEffect() public {
        ListConfig memory c = _listConfig(Polarity.DENY, Mode.ENUMERATED);
        c.noticePeriod = 3 days;
        vm.prank(manager);
        bytes32 list = registry.createList(c, "");
        SubjectRef memory s = _account(alice);

        EntryInput memory input = _input();
        input.validFrom = uint64(T0 + 1 days); // sooner than the list promises
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.InvalidWindow.selector);
        registry.addEntry(list, s, input, "");

        _add(list, s);
        assertEq(registry.entryOf(list, _key(s)).validFrom, T0 + 3 days);
        _expect(_match(list, s), Match.NO_MATCH, R_ENTRY_PENDING);
        vm.warp(T0 + 3 days);
        _expect(_match(list, s), Match.MATCH, R_LISTED);
    }

    function test_objection_isRecordedAndChangesNothing() public {
        bytes32 list = _list(Polarity.DENY);
        SubjectRef memory s = _account(alice);
        bytes32 key = _add(list, s);
        bytes32 before = _state(list);

        vm.expectEmit();
        emit IAAFRegistry.ObjectionFiled(list, key, alice, keccak256("objection"), "ipfs://objection");
        vm.prank(alice);
        registry.fileObjection(list, key, keccak256("objection"), "ipfs://objection");

        assertEq(_state(list), before);
        _expect(_match(list, s), Match.MATCH, R_LISTED);
        vm.expectRevert(IAAFRegistry.EntryNotFound.selector);
        registry.fileObjection(list, _key(_account(bob)), keccak256("objection"), "");
    }

    function test_controllerTiedEntry_holdsOnlyForThatController() public {
        bytes32 list = _list(Polarity.ALLOW);
        vm.prank(alice);
        uint256 id = identities.register();
        SubjectRef memory s = _entry(address(identities), id);
        EntryInput memory input = _input();
        input.controller = alice;
        vm.prank(manager);
        registry.addEntry(list, s, input, "");

        Request memory r;
        _expect(registry.matchOf(list, s, r, ""), Match.UNDETERMINED, R_CONTROLLER_UNKNOWN);
        r.controller = alice;
        _expect(registry.matchOf(list, s, r, ""), Match.MATCH, R_LISTED);
        r.controller = bob;
        _expect(registry.matchOf(list, s, r, ""), Match.NO_MATCH, R_CONTROLLER_CHANGED);
    }

    // ------------------------------------------------------------ management

    // ------------------------------------------------------------ code of an account

    function test_codePin_holdsOnlyWhileTheAccountHasThatCode() public {
        bytes32 list = _list(Polarity.ALLOW);
        address account = address(new ScriptedEvaluator());
        SubjectRef memory s = _account(account);
        EntryInput memory input = _input();
        input.codeHash = account.codehash;
        vm.expectEmit();
        emit IAAFRegistry.EntryAdded(
            list, _key(s), s, 1, uint64(T0), 0, Basis.DESIGNATION, bytes32(0), "TEST", address(0), account.codehash, ""
        );
        vm.prank(manager);
        registry.addEntry(list, s, input, "");
        assertEq(registry.entryOf(list, _key(s)).codeHash, account.codehash);

        Finding memory f = _match(list, s);
        _expect(f, Match.MATCH, R_LISTED);
        // Code can change without the list changing, so the result is for this call only.
        assertEq(f.validUntil, 0);

        // The account is the same address and now runs other code. The list did not change.
        bytes32 before = _state(list);
        vm.etch(account, hex"600160005260206000f3");
        f = _match(list, s);
        _expect(f, Match.UNDETERMINED, R_CODE_CHANGED);
        assertEq(f.validUntil, 0);
        assertEq(_state(list), before);
        (Match m, bytes32 reason) = registry.check(list, s);
        assertEq(m, Match.UNDETERMINED);
        assertEq(reason, R_CODE_CHANGED);
    }

    function test_codePin_followsTheDelegationOfAnAccount() public {
        bytes32 plain = _list(Polarity.ALLOW);
        bytes32 delegated = _list(Polarity.ALLOW);
        bytes32 untied = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        address first = makeAddr("implementation 1");
        address second = makeAddr("implementation 2");

        // One list admits alice as an account without code, one as delegating to `first`, and one
        // by address alone.
        EntryInput memory input = _input();
        input.codeHash = keccak256("");
        vm.prank(manager);
        registry.addEntry(plain, s, input, "");
        input.codeHash = keccak256(abi.encodePacked(hex"ef0100", first));
        vm.prank(manager);
        registry.addEntry(delegated, s, input, "");
        _add(untied, s);
        bytes32 before = keccak256(abi.encode(_state(plain), _state(delegated), _state(untied)));

        // No code, whether or not the account exists yet.
        _codeRow(plain, delegated, untied, s, true, false);
        // A delegated account carries the designation as its code; reading its code hash reads that.
        vm.etch(alice, abi.encodePacked(hex"ef0100", first));
        _codeRow(plain, delegated, untied, s, false, true);
        // Delegating elsewhere is a change of code at the same address.
        vm.etch(alice, abi.encodePacked(hex"ef0100", second));
        _codeRow(plain, delegated, untied, s, false, false);
        // Clearing the delegation restores the account without code.
        vm.etch(alice, "");
        _codeRow(plain, delegated, untied, s, true, false);

        // None of this was an act of the manager, and no state hash moved.
        assertEq(keccak256(abi.encode(_state(plain), _state(delegated), _state(untied))), before);
    }

    function _codeRow(bytes32 plain, bytes32 delegated, bytes32 untied, SubjectRef memory s, bool isPlain, bool isDelegated)
        internal
        view
    {
        Finding memory f = _match(plain, s);
        if (isPlain) _expect(f, Match.MATCH, R_LISTED);
        else _expect(f, Match.UNDETERMINED, R_CODE_CHANGED);
        assertEq(f.validUntil, 0);
        f = _match(delegated, s);
        if (isDelegated) _expect(f, Match.MATCH, R_LISTED);
        else _expect(f, Match.UNDETERMINED, R_CODE_CHANGED);
        assertEq(f.validUntil, 0);
        f = _match(untied, s);
        _expect(f, Match.MATCH, R_LISTED);
        assertEq(f.validUntil, type(uint64).max);
    }

    function test_codePin_isOptional() public {
        bytes32 list = _list(Polarity.DENY);
        address account = address(new ScriptedEvaluator());
        SubjectRef memory s = _account(account);
        _add(list, s);
        vm.etch(account, hex"600160005260206000f3");
        // An entry made by address alone says nothing about code and holds whatever the code is.
        Finding memory f = _match(list, s);
        _expect(f, Match.MATCH, R_LISTED);
        assertEq(f.validUntil, type(uint64).max);
    }

    function test_codePin_onlyWhereTheCodeCanBeRead() public {
        bytes32 list = _list(Polarity.ALLOW);
        EntryInput memory input = _input();
        input.codeHash = keccak256("");
        vm.startPrank(manager);
        // A registry entry has an owner, not code.
        vm.expectRevert(IAAFRegistry.CodePinNotSupported.selector);
        registry.addEntry(list, _entry(address(identities), 1), input, "");
        // An artefact is identified by its digest already.
        vm.expectRevert(IAAFRegistry.CodePinNotSupported.selector);
        registry.addEntry(list, _artefact(keccak256("package")), input, "");
        // An account on another chain cannot be read from here.
        SubjectRef memory elsewhere = _account(alice);
        elsewhere.chainId = block.chainid + 1;
        vm.expectRevert(IAAFRegistry.CodePinNotSupported.selector);
        registry.addEntry(list, elsewhere, input, "");
        vm.stopPrank();
    }

    function test_codePin_andWindow() public {
        bytes32 list = _list(Polarity.ALLOW);
        SubjectRef memory s = _account(alice);
        EntryInput memory input = _input();
        input.codeHash = keccak256("");
        input.validFrom = uint64(T0 + 100);
        vm.prank(manager);
        registry.addEntry(list, s, input, "");
        // Before the entry is in effect the answer does not depend on the code.
        Finding memory f = _match(list, s);
        _expect(f, Match.NO_MATCH, R_ENTRY_PENDING);
        assertEq(f.validUntil, T0 + 99);
        vm.warp(T0 + 100);
        _expect(_match(list, s), Match.MATCH, R_LISTED);
    }

    function test_state_changesWithEveryActOfTheManager() public {
        bytes32 list = _list(Polarity.ALLOW);
        bytes32 s0 = _state(list);
        bytes32 key = _add(list, _account(alice));
        bytes32 s1 = _state(list);
        vm.prank(manager);
        registry.suspendEntry(list, key, "X");
        bytes32 s2 = _state(list);
        bytes32 criteriaId = registry.registerCriteria(keccak256("doc/2"), address(0), bytes32(0), 0, "");
        vm.prank(manager);
        registry.setCriteria(list, criteriaId);
        bytes32 s3 = _state(list);
        assertTrue(s0 != s1 && s1 != s2 && s2 != s3);
        (uint64 revision,) = registry.stateOf(list);
        assertEq(revision, 4);
    }

    function test_manager_handOverTakesTwoSteps() public {
        bytes32 list = _list(Polarity.ALLOW);
        bytes32 before = _state(list);
        vm.prank(mallory);
        vm.expectRevert(IAAFRegistry.NotManager.selector);
        registry.offerManager(list, mallory);

        vm.prank(manager);
        registry.offerManager(list, bob);
        assertEq(registry.listOf(list).manager, manager);
        vm.prank(mallory);
        vm.expectRevert(IAAFRegistry.NotCandidate.selector);
        registry.acceptManager(list);

        vm.expectEmit();
        emit IAAFRegistry.ManagerChanged(list, manager, bob);
        vm.prank(bob);
        registry.acceptManager(list);
        assertEq(registry.listOf(list).manager, bob);
        assertTrue(_state(list) != before); // whoever pinned the list sees the change

        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.NotManager.selector);
        registry.addEntry(list, _account(alice), _input(), "");
    }

    function test_closedList_saysNothingAndAcceptsNothing() public {
        bytes32 list = _list(Polarity.DENY);
        _add(list, _account(alice));
        vm.prank(manager);
        registry.closeList(list);
        // A closed list is not read as "nobody is listed".
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_LIST_CLOSED);
        _expect(_match(list, _account(bob)), Match.UNDETERMINED, R_LIST_CLOSED);
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.ListIsClosed.selector);
        registry.addEntry(list, _account(bob), _input(), "");
    }

    function test_wrongMode_isRefused() public {
        bytes32 list = _list(Polarity.ALLOW);
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.WrongMode.selector);
        registry.commitSet(list, keccak256("root"), SetKind.SORTED, 4, "");
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.WrongMode.selector);
        registry.setSourcePin(list, keccak256("pin"));

        bytes32 predicate = _predicateList(Polarity.ALLOW, address(evaluator));
        vm.prank(manager);
        vm.expectRevert(IAAFRegistry.WrongMode.selector);
        registry.addEntry(predicate, _account(alice), _input(), "");
    }
}
