// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BaseFixture} from "../BaseFixture.sol";
import {MockStrategy} from "../mock/MockStrategy.sol";
import {MockToken} from "../mock/MockToken.sol";

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

    // ========================
    // ===== Config Tests =====
    // ========================

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
        for (uint256 i; i < NUM_EMITS; ++i) {
            assertTrue(strategy.isProtectedToken(EMITS[i]));
        }
    }

    function testIsProtectedTokenFailsForAddressZero() public {
        vm.expectRevert("Address 0");
        strategy.isProtectedToken(address(0));
    }

    // ============================
    // ===== Permission Tests =====
    // ============================

    function testGovernanceCanPause() public {
        vm.prank(governance);
        strategy.pause();

        assertTrue(strategy.paused());
    }

    function testGuardianCanPause() public {
        vm.prank(governance);
        strategy.pause();
    }

    function testGovernanceCanUnpause() public {
        vm.startPrank(governance);
        strategy.pause();
        strategy.unpause();

        assertFalse(strategy.paused());
    }

    function testGovernanceCanDeposit() public {
        vm.prank(governance);
        strategy.deposit();
    }

    function testKeeperCanDeposit() public {
        vm.prank(keeper);
        strategy.deposit();
    }

    function testVaultCanDeposit() public {
        vm.prank(address(vault));
        strategy.deposit();
    }

    function testGovernanceCanHarvest() public {
        vm.prank(governance);
        strategy.harvest();
    }

    function testKeeperCanHarvest() public {
        vm.prank(keeper);
        strategy.harvest();
    }

    function testHarvestOnce() public {
        depositAllChecked();

        uint256[] memory emitAmounts = new uint256[](NUM_EMITS);
        for (uint256 i; i < NUM_EMITS; ++i) {
            emitAmounts[i] = (i + 2) * 10**18;
        }

        harvestCheckedExact(1e18, emitAmounts);
    }

    // TODO: Checked from Vault.t.sol
    function testVaultCanWithdrawToVault() public {
        vm.prank(address(vault));
        strategy.withdrawToVault();
    }

    function testWithdrawOtherFailsForProtectedTokens() public {
        vm.prank(address(vault));
        vm.expectRevert("_onlyNotProtectedTokens");
        strategy.withdrawOther(WANT);
    }

    // TODO: Checked from Vault.t.sol
    function testVaultCanWithdrawOther() public {
        MockToken extra = new MockToken("extra", "EXTR");
        extra.mint(address(vault), 100);

        vm.prank(address(vault));
        strategy.withdrawOther(address(extra));
    }

    function testCantWithdrawZeroAmount() public {
        vm.prank(address(vault));
        vm.expectRevert("Amount 0");
        strategy.withdraw(0);
    }

    // TODO: Generalize, checked from Vault.t.sol
    function testVaultCanWithdraw() public {
        IERC20(WANT).transfer(address(strategy), 1);

        vm.prank(address(vault));
        strategy.withdraw(1);

        assertEq(IERC20(WANT).balanceOf(address(strategy)), 0);
        assertEq(IERC20(WANT).balanceOf(address(vault)), 1);
    }
}

/*
TODO:
- Tend tests
- Strategy improvements:
  - Less asserts/gas improvements
  - BaseStrategy => Strategy
*/
