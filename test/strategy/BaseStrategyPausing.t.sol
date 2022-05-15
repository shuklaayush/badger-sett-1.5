// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "../BaseFixture.sol";

contract BaseStrategyPausingTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // =========================
    // ===== Pausing Tests =====
    // =========================

    function testHarvestFailsWhenPaused() public {
        vm.prank(governance);
        strategy.pause();

        vm.expectRevert("Pausable: paused");
        strategy.harvest();
    }
}
