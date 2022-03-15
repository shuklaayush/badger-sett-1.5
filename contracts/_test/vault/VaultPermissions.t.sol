// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "../BaseFixture.sol";

contract VaultPermissionsTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // ==================
    // =====  Tests =====
    // ==================

    function testSetTreasuryIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setTreasury(address(this));
    }

    function testSetGuestListIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setGuestList(address(this));
    }

    function testSetGuardianIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setGuardian(address(this));
    }

    function testSetToEarnIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setToEarnBps(1_000);
    }

    function testSetMaxPerformanceFeeIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxPerformanceFee(1_000);
    }

    function testSetMaxWithdrawalFeeIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxWithdrawalFee(1_000);
    }

    function testSetMaxManagementFeeIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxManagementFee(1_000);
    }

    function testSetPerformanceFeeStrategistIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setPerformanceFeeStrategist(1_000);
    }

    function testSetPerformanceFeeGovernanceIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setPerformanceFeeGovernance(1_000);
    }

    function testSetWithdrawalFeeIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setWithdrawalFee(1_000);
    }

    function testSetManagementFeeIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setManagementFee(1_000);
    }

    function testSetStrategistIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setStrategist(address(this));
    }

    function testSetKeeperIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setKeeper(address(this));
    }

    function testSetGovernanceIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setGovernance(address(this));
    }

    function testSetStrategyIsPermissioned() public {
        vm.expectRevert("onlyGovernance");
        vault.setStrategy(address(this));
    }

    function testEarnIsPermissioned() public {
        vm.expectRevert("onlyAuthorizedActors");
        vault.earn();
    }

    function testEmitNonProtectedTokenIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.emitNonProtectedToken(address(0));
    }

    function testWithdrawToVaultIsPermissioned() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.withdrawToVault();
    }

    function testReportHarvestIsPermissioned() public {
        vm.expectRevert("onlyStrategy");
        vault.reportHarvest(0);
    }

    function testReportAdditionalTokenIsPermissioned() public {
        vm.expectRevert("onlyStrategy");
        vault.reportAdditionalToken(EMITS[0]);
    }

    function testPauseIsPermissioned() public {
        vm.expectRevert("onlyPausers");
        vault.pause();
    }

    function testUnpauseIsPermissioned() public {
        vm.prank(governance);
        vault.pause();

        vm.expectRevert("onlyGovernance");
        vault.unpause();
    }
}
