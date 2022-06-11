// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "../BaseFixture.sol";

contract BaseStrategyPermissionsTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // ============================
    // ===== Permission Tests =====
    // ============================

    function testSetWithdrawalMaxDeviationThresholdIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        strategy.setWithdrawalMaxDeviationThreshold(0);
    }

    function testDepositIsPermissioned() public {
        vm.expectRevert("onlyAuthorizedActorsOrVault");
        strategy.deposit();
    }

    function testHarvestIsPermissioned() public {
        vm.expectRevert("onlyAuthorizedActors");
        strategy.harvest();
    }

    function testTendIsPermissioned() public {
        vm.expectRevert("onlyAuthorizedActors");
        strategy.tend();
    }

    function testWithdrawToVaultIsPermissioned() public {
        vm.expectRevert("onlyVault");
        strategy.withdrawToVault();
    }

    function testWithdrawOtherIsPermissioned() public {
        vm.expectRevert("onlyVault");
        strategy.withdrawOther(address(0));
    }

    function testWithdrawIsPermissioned() public {
        vm.expectRevert("onlyVault");
        strategy.withdraw(1);
    }

    function testPauseIsPermissioned() public {
        vm.expectRevert("onlyPausers");
        strategy.pause();
    }

    function testUnpauseIsPermissioned() public {
        vm.prank(governance);
        strategy.pause();

        vm.expectRevert("onlyGovernance");
        strategy.unpause();
    }
}

/*
TODO:
- Fuzz and vm.assume()
*/
