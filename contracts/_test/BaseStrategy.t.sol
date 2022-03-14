// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "./BaseFixture.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

contract BaseStrategyTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // ============================
    // ===== Deployment Tests =====
    // ============================

    function testVaultIsSetProperly() public {
        assertEq(strategy.vault(), address(vault));
    }

    function testGovernanceIsSetProperly() public {
        assertEq(strategy.governance(), governance);
    }

    function testKeeperIsSetProperly() public {
        assertEq(strategy.keeper(), keeper);
    }

    function testGuardianIsSetProperly() public {
        assertEq(strategy.guardian(), guardian);
    }

    function testWithdrawalMaxDeviationThresholdIsSetProperly() public {
        assertEq(strategy.withdrawalMaxDeviationThreshold(), 50);
    }

    function testMaxBpsIsSetProperly() public {
        assertEq(strategy.MAX_BPS(), 10_000);
    }

    function testInitializeFailsWhenVaultIsAddressZero() public {
        MockStrategy mockStrategy = new MockStrategy();
        vm.expectRevert("Address 0");
        mockStrategy.initialize(address(0), new address[](0));
    }

    /// ========================
    /// ===== Config Tests =====
    /// ========================

    function testSetWithdrawalMaxDeviationThresholdIsProtected() public {
        vm.expectRevert("onlyGovernance");
        strategy.setWithdrawalMaxDeviationThreshold(0);
    }

    function testGovernanceCanSetWithdrawalMaxDeviationThreshold() public {
        vm.prank(governance);
        strategy.setWithdrawalMaxDeviationThreshold(10);

        assertEq(strategy.withdrawalMaxDeviationThreshold(), 10);
    }

    function testSetWithdrawalMaxDeviationThresholdFailsWhenMoreThanMax()
        public
    {
        vm.prank(governance);
        vm.expectRevert("_threshold should be <= MAX_BPS");
        strategy.setWithdrawalMaxDeviationThreshold(100_000);
    }

    function testWantIsProtectedToken() public {
        assertTrue(strategy.isProtectedToken(WANT));
    }

    function testEmittedIsProtectedToken() public {
        uint256 numRewards = EMITS.length;
        for (uint256 i; i < numRewards; ++i) {
            assertTrue(strategy.isProtectedToken(EMITS[i]));
        }
    }

    function testIsProtectedTokenFailsForAddressZero() public {
        vm.expectRevert("Address 0");
        strategy.isProtectedToken(address(0));
    }
}

/*
TODO:
- Strategy improvements:
  - Take want from vault
  - Less asserts/gas improvements
  - BaseStrategy => Strategy
*/
