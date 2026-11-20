// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./AWFBase.sol";

contract AWFPredicateTest is AWFBase {
    ScriptedEvaluator internal evaluator;
    bytes32 internal list;

    function setUp() public override {
        super.setUp();
        evaluator = new ScriptedEvaluator();
        list = _predicateList(Polarity.ALLOW, address(evaluator));
    }

    function test_evaluatorDecidesMembership() public {
        evaluator.set(Match.MATCH);
        Finding memory f = _match(list, _account(alice));
        _expect(f, Match.MATCH, "SCRIPTED");
        assertEq(f.criteriaId, registry.listOf(list).criteriaId);
        evaluator.set(Match.NO_MATCH);
        _expect(_match(list, _account(alice)), Match.NO_MATCH, "SCRIPTED");
        evaluator.set(Match.UNDETERMINED);
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, "SCRIPTED");
    }

    function test_validityComesFromTheEvaluator() public {
        evaluator.set(Match.MATCH);
        evaluator.setValidUntil(uint64(T0 + 60));
        assertEq(_match(list, _account(alice)).validUntil, T0 + 60);
    }

    function test_failingEvaluator_isUndetermined() public {
        evaluator.set(Match.MATCH);
        evaluator.setFault(1); // reverts
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_FAILED);
        evaluator.setFault(3); // answers outside the three values
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_FAILED);
        evaluator.setFault(4); // answers in another shape
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_FAILED);
    }

    function test_evaluatorThatNeverReturns_isCutOff() public {
        evaluator.set(Match.MATCH);
        evaluator.setFault(2);
        uint256 before = gasleft();
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_FAILED);
        assertLt(before - gasleft(), registry.MODULE_GAS() + 300_000);
    }

    function test_changedConfiguration_stopsTheList() public {
        evaluator.set(Match.MATCH);
        evaluator.setConfig(keccak256("config/2"));
        // The same address now applies other rules. The criteria the list names no longer describe it.
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_CHANGED);

        // The manager adopts the new version explicitly; the list state shows it.
        bytes32 before = _state(list);
        bytes32 criteriaId = registry.registerCriteria(keccak256("criteria"), address(evaluator), bytes32(0), 0, "");
        vm.expectEmit();
        emit IAWFRegistry.CriteriaSet(list, criteriaId);
        vm.prank(manager);
        registry.setCriteria(list, criteriaId);
        assertTrue(_state(list) != before);
        _expect(_match(list, _account(alice)), Match.MATCH, "SCRIPTED");
    }

    function test_changedCode_stopsTheList() public {
        evaluator.set(Match.MATCH);
        ScriptedRelation other = new ScriptedRelation();
        vm.etch(address(evaluator), address(other).code);
        _expect(_match(list, _account(alice)), Match.UNDETERMINED, R_MODULE_CHANGED);
    }

    function test_setCriteria_mustFitTheMode() public {
        bytes32 plain = registry.registerCriteria(keccak256("doc"), address(0), bytes32(0), 0, "");
        vm.prank(manager);
        vm.expectRevert(IAWFRegistry.InvalidConfig.selector);
        registry.setCriteria(list, plain);
        vm.prank(manager);
        vm.expectRevert(IAWFRegistry.InvalidConfig.selector);
        registry.setCriteria(list, bytes32(0));
        vm.prank(mallory);
        vm.expectRevert(IAWFRegistry.NotManager.selector);
        registry.setCriteria(list, plain);
    }

    function test_checkWithoutEvidence_reachesTheEvaluator() public {
        evaluator.set(Match.NO_MATCH);
        (Match m, bytes32 reason) = registry.check(list, _account(alice));
        assertEq(m, Match.NO_MATCH);
        assertEq(reason, "SCRIPTED");
    }
}
