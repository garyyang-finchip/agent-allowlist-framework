// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AAFBase.sol";

contract AAFSetsTest is AAFBase {
    bytes32 internal list;
    bytes32[] internal keys; // sorted, with the two sentinels
    bytes32[][] internal levels;

    function setUp() public override {
        super.setUp();
        ListConfig memory c = _listConfig(Polarity.DENY, Mode.COMMITTED);
        vm.prank(manager);
        list = registry.createList(c, "");
        _commit(_sortedKeys(5), SetKind.SORTED);
    }

    /// @dev `n` member keys between the two sentinels, in ascending order.
    function _sortedKeys(uint256 n) internal view returns (bytes32[] memory k) {
        k = new bytes32[](n + 2);
        for (uint256 i; i < n; ++i) k[i + 1] = _key(_account(address(uint160(0x1000 + i))));
        // insertion sort of the member keys
        for (uint256 i = 2; i <= n; ++i) {
            bytes32 x = k[i];
            uint256 j = i;
            while (j > 1 && k[j - 1] > x) {
                k[j] = k[j - 1];
                --j;
            }
            k[j] = x;
        }
        k[n + 1] = bytes32(type(uint256).max);
    }

    function _commit(bytes32[] memory k, SetKind kind) internal {
        keys = k;
        bytes32[][] memory l = SetTree.build(k);
        delete levels;
        for (uint256 i; i < l.length; ++i) levels.push(l[i]);
        vm.prank(manager);
        registry.commitSet(list, SetTree.root(l), kind, uint64(k.length), "ipfs://set");
    }

    function _subjectAt(uint256 index) internal view returns (SubjectRef memory s, uint256 position) {
        // the member whose key sits at `index` of the sorted set
        for (uint256 i; i < keys.length - 2; ++i) {
            s = _account(address(uint160(0x1000 + i)));
            if (_key(s) == keys[index]) return (s, index);
        }
        revert("no member at index");
    }

    function _lowIndex(bytes32 key) internal view returns (uint256 low) {
        while (keys[low + 1] < key) ++low;
    }

    function test_noSetCommitted_isUndetermined() public {
        ListConfig memory c = _listConfig(Polarity.DENY, Mode.COMMITTED);
        vm.prank(manager);
        bytes32 empty = registry.createList(c, "");
        _expect(_match(empty, _account(alice)), Match.UNDETERMINED, R_SET_MISSING);
    }

    function test_withoutProof_nothingIsKnown() public view {
        // Showing no proof of membership in a deny list is not proof of absence from it.
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_PROOF_MISSING);
    }

    function test_membershipProof() public view {
        (SubjectRef memory s, uint256 index) = _subjectAt(3);
        Finding memory f = _match(list, s, SetTree.memberProof(levels, index));
        _expect(f, Match.MATCH, R_SET_MEMBER);
        assertEq(f.basis, SetTree.root(levels));
    }

    function test_membershipProof_forAnotherKeyFails() public view {
        (, uint256 index) = _subjectAt(3);
        _expect(_match(list, _account(alice), SetTree.memberProof(levels, index)), Match.UNDETERMINED, R_PROOF_INVALID);
    }

    function test_absenceProof_confirmsNoMatch() public view {
        SubjectRef memory s = _account(alice);
        uint256 low = _lowIndex(_key(s));
        Finding memory f = _match(list, s, SetTree.absenceProof(levels, keys, low));
        _expect(f, Match.NO_MATCH, R_SET_NON_MEMBER);
        assertEq(f.validUntil, type(uint64).max);
    }

    function test_absenceProof_cannotBeMadeForAMember() public view {
        (SubjectRef memory s,) = _subjectAt(2);
        // Whatever pair of neighbours is offered, a member's key is never strictly between them.
        for (uint256 low; low + 1 < keys.length; ++low) {
            _expect(_match(list, s, SetTree.absenceProof(levels, keys, low)), Match.UNDETERMINED, R_PROOF_INVALID);
        }
    }

    function test_absenceProof_neighboursMustBeAdjacent() public view {
        SubjectRef memory s = _account(alice);
        uint256 low = _lowIndex(_key(s));
        SetProof memory p;
        p.index = low == 0 ? 0 : low - 1; // leaves two apart
        p.path = SetTree.path(levels, p.index);
        p.lowKey = keys[p.index];
        p.highKey = keys[low + 1];
        p.highPath = SetTree.path(levels, low + 1);
        if (low != 0) _expect(_match(list, s, abi.encode(p)), Match.UNDETERMINED, R_PROOF_INVALID);
    }

    function test_membershipOnlySet_leavesNegativeQueriesOpen() public {
        _commit(keys, SetKind.MEMBERSHIP);
        (SubjectRef memory member, uint256 index) = _subjectAt(1);
        _expect(_match(list, member, SetTree.memberProof(levels, index)), Match.MATCH, R_SET_MEMBER);
        SubjectRef memory s = _account(alice);
        Finding memory f = _match(list, s, SetTree.absenceProof(levels, keys, _lowIndex(_key(s))));
        _expect(f, Match.UNDETERMINED, R_NEGATIVE_UNSUPPORTED);
    }

    function test_newRoot_retiresOldProofs() public {
        SubjectRef memory s = _account(alice);
        bytes memory oldProof = SetTree.absenceProof(levels, keys, _lowIndex(_key(s)));
        _expect(_match(list, s, oldProof), Match.NO_MATCH, R_SET_NON_MEMBER);
        bytes32 before = _state(list);

        // The manager adds the subject and commits the new set.
        bytes32[] memory grown = new bytes32[](keys.length + 1);
        uint256 low = _lowIndex(_key(s));
        for (uint256 i; i <= low; ++i) grown[i] = keys[i];
        grown[low + 1] = _key(s);
        for (uint256 i = low + 1; i < keys.length; ++i) grown[i + 1] = keys[i];
        _commit(grown, SetKind.SORTED);

        assertTrue(_state(list) != before);
        _expect(_match(list, s, oldProof), Match.UNDETERMINED, R_PROOF_INVALID);
        _expect(_match(list, s, SetTree.memberProof(levels, low + 1)), Match.MATCH, R_SET_MEMBER);
    }

    function test_malformedEvidence_isUndeterminedNotARevert() public view {
        _expect(_match(list, _account(alice), hex"deadbeef"), Match.UNDETERMINED, R_PROOF_INVALID);
        _expect(_match(list, _account(alice), abi.encode(uint256(1))), Match.UNDETERMINED, R_PROOF_INVALID);
        SetProof memory p;
        p.member = true;
        p.index = 99; // outside the set
        p.path = SetTree.path(levels, 0);
        _expect(_match(list, _account(alice), abi.encode(p)), Match.UNDETERMINED, R_PROOF_INVALID);
        p.index = 0;
        p.path = new bytes32[](1); // wrong depth
        _expect(_match(list, _account(alice), abi.encode(p)), Match.UNDETERMINED, R_PROOF_INVALID);
    }

    function test_commitSet_refusesEmptyCommitments() public {
        vm.startPrank(manager);
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.commitSet(list, bytes32(0), SetKind.SORTED, 4, "");
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.commitSet(list, keccak256("root"), SetKind.NONE, 4, "");
        vm.expectRevert(IAAFRegistry.InvalidConfig.selector);
        registry.commitSet(list, keccak256("root"), SetKind.SORTED, 0, "");
        vm.stopPrank();
    }

    function testFuzz_everyAbsentKeyHasAProof_noMemberHasOne(uint8 size, bytes32 probe) public {
        uint256 n = bound(size, 1, 20);
        _commit(_sortedKeys(n), SetKind.SORTED);
        vm.assume(probe != bytes32(0) && probe != bytes32(type(uint256).max));
        bool member;
        for (uint256 i = 1; i <= n; ++i) member = member || keys[i] == probe;
        uint256 low = _lowIndex(probe);
        (Match m,) = registry.verifySetProof(
            SetTree.root(levels), SetKind.SORTED, uint64(keys.length), probe, SetTree.absenceProof(levels, keys, low)
        );
        assertEq(m, member ? Match.UNDETERMINED : Match.NO_MATCH);
        for (uint256 i = 1; i <= n; ++i) {
            (m,) = registry.verifySetProof(
                SetTree.root(levels), SetKind.SORTED, uint64(keys.length), keys[i], SetTree.memberProof(levels, i)
            );
            assertEq(m, Match.MATCH);
        }
    }
}
