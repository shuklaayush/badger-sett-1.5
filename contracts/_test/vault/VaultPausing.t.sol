// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "../BaseFixture.sol";

contract VaultPausingTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // =================
    // ===== Tests =====
    // =================

    function testSetGuestListFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setGuestList(address(this));
    }

    function testSetToEarnBpsFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setToEarnBps(100_000);
    }

    function testSetPerformanceFeeStrategistFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setPerformanceFeeStrategist(100);
    }

    function testSetPerformanceFeeGovernanceFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setPerformanceFeeGovernance(100);
    }

    function testSetWithdrawalFeeFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setWithdrawalFee(100);
    }

    function testSetManagementFeeFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setManagementFee(100);
    }

    function testDepositFailsWhenPaused() public {
        vm.prank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.deposit(1);
    }

    function testDepositFailsWhenDepositsArePaused() public {
        vm.prank(governance);
        vault.pauseDeposits();

        vm.expectRevert("pausedDeposit");
        vault.deposit(1);
    }

    function testWithdrawFailsWhenPaused() public {
        vm.prank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1);
    }

    function testWithdrawAllFailsWhenPaused() public {
        vm.prank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.withdraw(1);
    }
}
