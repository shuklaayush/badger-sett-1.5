// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseFixture} from "./BaseFixture.sol";
import {Vault} from "../Vault.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract VaultTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // ======================
    // ===== Unit Tests =====
    // ======================

    // ========================
    // ===== Config Tests =====
    // ========================

    function testSetTreasuryIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setTreasury(address(this));
    }

    function testGovernanceCanSetTreasury() public {
        vm.prank(governance);
        vault.setTreasury(address(this));

        assertEq(vault.treasury(), address(this));
    }

    function testTreasuryCantBeSetToZero() public {
        vm.prank(governance);
        vm.expectRevert("Address 0");
        vault.setTreasury(address(0));
    }

    function testSetGuestListIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setGuestList(address(this));
    }

    function testGovernanceCanSetGuestList() public {
        vm.prank(governance);
        vault.setGuestList(address(this));

        assertEq(address(vault.guestList()), address(this));
    }

    function testStrategistCanSetGuestList() public {
        vm.prank(strategist);
        vault.setGuestList(address(this));

        assertEq(address(vault.guestList()), address(this));
    }

    function testSetGuestListFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setGuestList(address(this));
    }

    function testSetGuardianIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setGuardian(address(this));
    }

    function testGovernanceCanSetGuardian() public {
        vm.prank(governance);
        vault.setGuardian(address(this));

        assertEq(vault.guardian(), address(this));
    }

    function testGuardianCantBeSetToZero() public {
        vm.prank(governance);
        vm.expectRevert("Address cannot be 0x0");
        vault.setGuardian(address(0));
    }

    function testSetToEarnIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setToEarnBps(1_000);
    }

    function testGovernanceCanSetToEarnBps() public {
        vm.prank(governance);
        vault.setToEarnBps(1_000);

        assertEq(vault.toEarnBps(), 1_000);
    }

    function testStrategistCanSetToEarnBps() public {
        vm.prank(strategist);
        vault.setToEarnBps(1_000);

        assertEq(vault.toEarnBps(), 1_000);
    }

    function testSetToEarnBpsFailsWhenMoreThanMax() public {
        vm.prank(governance);
        vm.expectRevert("toEarnBps should be <= MAX_BPS");
        vault.setToEarnBps(100_000);
    }

    function testSetToEarnBpsFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setToEarnBps(100_000);
    }

    function testSetMaxPerformanceFeeIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxPerformanceFee(1_000);
    }

    function testGovernanceCanSetMaxPerformanceFee() public {
        vm.prank(governance);
        vault.setMaxPerformanceFee(1_000);

        assertEq(vault.maxPerformanceFee(), 1_000);
    }

    function testSetMaxPerformanceFeeFailsWhenMoreThanMax() public {
        vm.prank(governance);
        vm.expectRevert("performanceFee too high");
        vault.setMaxPerformanceFee(100_000);
    }

    function testSetMaxWithdrawalFeeIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxWithdrawalFee(1_000);
    }

    function testGovernanceCanSetMaxWithdrawalFee() public {
        vm.prank(governance);
        vault.setMaxWithdrawalFee(200);

        assertEq(vault.maxWithdrawalFee(), 200);
    }

    function testSetMaxWithdrawalFeeFailsWhenMoreThanMax() public {
        vm.prank(governance);
        vm.expectRevert("withdrawalFee too high");
        vault.setMaxWithdrawalFee(100_000);
    }

    function testSetMaxManagementFeeIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setMaxManagementFee(1_000);
    }

    function testGovernanceCanSetMaxManagementFee() public {
        vm.prank(governance);
        vault.setMaxManagementFee(100);

        assertEq(vault.maxManagementFee(), 100);
    }

    function testSetMaxManagementFeeFailsWhenMoreThanMax() public {
        vm.prank(governance);
        vm.expectRevert("managementFee too high");
        vault.setMaxManagementFee(100_000);
    }

    function testSetPerformanceFeeStrategistIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setPerformanceFeeStrategist(1_000);
    }

    function testGovernanceCanSetPerformanceFeeStrategist() public {
        vm.prank(governance);
        vault.setPerformanceFeeStrategist(100);

        assertEq(vault.performanceFeeStrategist(), 100);
    }

    function testStrategistCanSetPerformanceFeeStrategist() public {
        vm.prank(strategist);
        vault.setPerformanceFeeStrategist(100);

        assertEq(vault.performanceFeeStrategist(), 100);
    }

    function testSetPerformanceFeeStrategistFailsWhenMoreThanMax() public {
        uint256 maxPerformanceFee = vault.maxPerformanceFee();

        vm.prank(governance);
        vm.expectRevert("Excessive strategist performance fee");
        vault.setPerformanceFeeStrategist(maxPerformanceFee + 1);
    }

    function testSetPerformanceFeeStrategistFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setPerformanceFeeStrategist(100);
    }

    function testSetPerformanceFeeGovernanceIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setPerformanceFeeGovernance(1_000);
    }

    function testGovernanceCanSetPerformanceFeeGovernance() public {
        vm.prank(governance);
        vault.setPerformanceFeeGovernance(100);

        assertEq(vault.performanceFeeGovernance(), 100);
    }

    function testStrategistCanSetPerformanceFeeGovernance() public {
        vm.prank(strategist);
        vault.setPerformanceFeeGovernance(100);

        assertEq(vault.performanceFeeGovernance(), 100);
    }

    function testSetPerformanceFeeGovernanceFailsWhenMoreThanMax() public {
        uint256 maxPerformanceFee = vault.maxPerformanceFee();

        vm.prank(governance);
        vm.expectRevert("Excessive governance performance fee");
        vault.setPerformanceFeeGovernance(maxPerformanceFee + 1);
    }

    function testSetPerformanceFeeGovernanceFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setPerformanceFeeGovernance(100);
    }

    function testSetWithdrawalFeeIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setWithdrawalFee(1_000);
    }

    function testGovernanceCanSetWithdrawalFee() public {
        vm.prank(governance);
        vault.setWithdrawalFee(100);

        assertEq(vault.withdrawalFee(), 100);
    }

    function testStrategistCanSetWithdrawalFee() public {
        vm.prank(strategist);
        vault.setWithdrawalFee(100);

        assertEq(vault.withdrawalFee(), 100);
    }

    function testSetWithdrawalFeeFailsWhenMoreThanMax() public {
        uint256 maxWithdrawalFee = vault.maxWithdrawalFee();

        vm.prank(governance);
        vm.expectRevert("Excessive withdrawal fee");
        vault.setWithdrawalFee(maxWithdrawalFee + 1);
    }

    function testSetWithdrawalFeeFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setWithdrawalFee(100);
    }

    function testSetManagementFeeIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.setManagementFee(1_000);
    }

    function testGovernanceCanSetManagementFee() public {
        vm.prank(governance);
        vault.setManagementFee(100);

        assertEq(vault.managementFee(), 100);
    }

    function testStrategistCanSetManagementFee() public {
        vm.prank(strategist);
        vault.setManagementFee(100);

        assertEq(vault.managementFee(), 100);
    }

    function testSetManagementFeeFailsWhenMoreThanMax() public {
        uint256 maxManagementFee = vault.maxManagementFee();

        vm.prank(governance);
        vm.expectRevert("Excessive management fee");
        vault.setManagementFee(maxManagementFee + 1);
    }

    function testSetManagementFeeFailsWhenPaused() public {
        vm.startPrank(governance);
        vault.pause();

        vm.expectRevert("Pausable: paused");
        vault.setManagementFee(100);
    }

    // TODO: Maybe move to SettAccessControlsTest

    function testSetStrategistIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setStrategist(address(this));
    }

    function testGovernanceCanSetStrategist() public {
        vm.prank(governance);
        vault.setStrategist(address(this));

        assertEq(vault.strategist(), address(this));
    }

    function testSetKeeperIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setKeeper(address(this));
    }

    function testGovernanceCanSetKeeper() public {
        vm.prank(governance);
        vault.setKeeper(address(this));

        assertEq(vault.keeper(), address(this));
    }

    function testSetGovernanceIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setGovernance(address(this));
    }

    function testGovernanceCanSetGovernance() public {
        vm.prank(governance);
        vault.setGovernance(address(this));

        assertEq(vault.governance(), address(this));
    }

    function testSetStrategyIsProtected() public {
        vm.expectRevert("onlyGovernance");
        vault.setStrategy(address(this));
    }

    function testSetStrategyFailsWithAddressZero() public {
        vm.prank(governance);
        vm.expectRevert("Address 0");
        vault.setStrategy(address(0));
    }

    function testSetStrategyFailsWhenNonZeroBalance() public {
        depositAllChecked();
        earnChecked();

        vm.prank(governance);
        vm.expectRevert("Please withdrawToVault before changing strat");
        vault.setStrategy(address(this));
    }

    function testGovernanceCanSetStrategy() public {
        vm.prank(governance);
        vm.expectEmit(true, false, false, false);
        emit SetStrategy(address(this));
        vault.setStrategy(address(this));

        assertEq(vault.strategy(), address(this));
    }

    // ============================
    // ===== Deployment Tests =====
    // ============================

    function testGovernanceIsSetProperly() public {
        assertEq(vault.governance(), governance);
    }

    function testKeeperIsSetProperly() public {
        assertEq(vault.keeper(), keeper);
    }

    function testGuardianIsSetProperly() public {
        assertEq(vault.guardian(), guardian);
    }

    function testTokenIsSetProperly() public {
        assertEq(address(vault.token()), WANT);
    }

    function testTreasuryIsSetProperly() public {
        assertEq(vault.treasury(), treasury);
    }

    function testToEarnBpsIsSetProperly() public {
        assertEq(vault.toEarnBps(), 9_500);
    }

    function testPerformanceFeeGovernanceIsSetProperly() public {
        assertEq(vault.performanceFeeGovernance(), PERFORMANCE_FEE_GOVERNANCE);
    }

    function testPerformanceFeeStrategistIsSetProperly() public {
        assertEq(vault.performanceFeeStrategist(), PERFORMANCE_FEE_STRATEGIST);
    }

    function testWithdrawalFeeIsSetProperly() public {
        assertEq(vault.withdrawalFee(), WITHDRAWAL_FEE);
    }

    function testManagementFeeIsSetProperly() public {
        assertEq(vault.managementFee(), MANAGEMENT_FEE);
    }

    function testMaxBpsIsSetProperly() public {
        assertEq(vault.MAX_BPS(), 10_000);
    }

    function testMaxPerformanceFeeIsSetProperly() public {
        assertEq(vault.maxPerformanceFee(), 3_000);
    }

    function testMaxWithdrawalFeeIsSetProperly() public {
        assertEq(vault.maxWithdrawalFee(), 200);
    }

    function testMaxManagementFeeIsSetProperly() public {
        assertEq(vault.maxManagementFee(), 200);
    }

    function testInitializeFailsWhenTokenIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            address(0),
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenGovernanceIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            address(0),
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenKeeperIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            governance,
            address(0),
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenGuardianIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            governance,
            keeper,
            address(0),
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenTreasuryIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            address(0),
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenStrategistIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            treasury,
            address(0),
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    function testInitializeFailsWhenBadgerTreeIsAddressZero() public {
        Vault testVault = new Vault();
        vm.expectRevert(bytes(""));
        testVault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            address(0),
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );
    }

    // ======================
    // ===== Name Tests =====
    // ======================

    function testInitializeWithNoName() public {
        assertEq(
            vault.name(),
            string.concat("Badger Sett ", IERC20Metadata(WANT).name())
        );
    }

    function testInitializeWithName() public {
        Vault testVault = new Vault();
        testVault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "Test Vault",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );

        assertEq(testVault.name(), "Test Vault");
    }

    function testInitializeWithNoSymbol() public {
        assertEq(
            vault.symbol(),
            string.concat("b", IERC20Metadata(WANT).symbol())
        );
    }

    function testInitializeWithSymbol() public {
        Vault testVault = new Vault();
        testVault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "TEST",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );

        assertEq(testVault.symbol(), "TEST");
    }

    function testVersion() public {
        assertEq(vault.version(), "1.5");
    }

    // =========================
    // ===== Deposit Tests =====
    // =========================

    function testDepositOnce() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositChecked(amount);
    }

    function testDepositFailsIfAmountIsZero() public {
        vm.expectRevert("Amount 0");
        vault.deposit(0);
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

    function testDepositAll() public {
        depositAllChecked();
    }

    function testDepositForOnce() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositForChecked(amount, rando);
    }

    // ======================
    // ===== Earn Tests =====
    // ======================

    function testGovernanceCanEarn() public {
        vm.prank(governance);
        vault.earn();
    }

    function testKeeperCanEarn() public {
        vm.prank(keeper);
        vault.earn();
    }

    function testEarnIsProtected() public {
        vm.expectRevert("onlyAuthorizedActors");
        vault.earn();
    }

    function testEarn() public {
        depositAllChecked();
        earnChecked();
    }

    function testEarnFailsWhenStrategyPaused() public {
        depositAllChecked();

        vm.startPrank(governance);
        strategy.pause();

        vm.expectRevert("Pausable: paused");
        vault.earn();
    }

    function testEarnFailsWhenDepositsArePaused() public {
        depositAllChecked();

        vm.startPrank(governance);
        vault.pauseDeposits();

        vm.expectRevert("pausedDeposit");
        vault.earn();
    }

    /// ==========================
    /// ===== Withdraw Tests =====
    /// ==========================

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

    function testWithdrawFailsIfAmountIsZero() public {
        vm.expectRevert("0 Shares");
        vault.withdraw(0);
    }

    function testWithdraw(uint256 sharesToWithdraw) public {
        uint256 shares = depositAllChecked();
        earnChecked();

        sharesToWithdraw = bound(sharesToWithdraw, 1, shares);
        withdrawChecked(sharesToWithdraw);
    }

    function testWithdrawBeforeEarn() public {
        uint256 shares = depositAllChecked();
        withdrawChecked(shares);
    }

    function testWithdrawTwice() public {
        uint256 shares = depositAllChecked();
        earnChecked();

        withdrawChecked(shares / 2);
        withdrawChecked(shares - shares / 2);
    }

    function testWithdrawAll() public {
        depositAllChecked();
        earnChecked();

        withdrawAllChecked();
    }

    // TODO: Fix this in BaseStrategy
    // function testWithdrawWithLossyStrategyFail() public {
    //     uint256 amount = IERC20(WANT).balanceOf(address(this));
    //     uint256 shares = depositChecked(amount);
    //     earnChecked();

    //     vm.prank(governance);
    //     strategy.setLossBps(10);

    //     withdrawChecked(9990509490509490510);
    // }

    // function testWithdrawWithLossyStrategy(uint256 sharesToWithdraw) public {
    //     uint256 amount = IERC20(WANT).balanceOf(address(this));
    //     uint256 shares = depositChecked(amount);
    //     earnChecked();

    //     vm.prank(governance);
    //     strategy.setLossBps(10);

    //     sharesToWithdraw = bound(sharesToWithdraw, 1, shares);
    //     withdrawChecked(sharesToWithdraw);
    // }

    function testWithdrawFailsWhenHighStrategyLoss() public {
        uint256 maxLoss = strategy.withdrawalMaxDeviationThreshold();

        uint256 amount = IERC20(WANT).balanceOf(address(this));
        uint256 shares = depositChecked(amount);
        earnChecked();

        vm.prank(governance);
        strategy.setLossBps(maxLoss + 1);

        vm.expectRevert("withdraw-exceed-max-deviation-threshold");
        vault.withdraw(shares);
    }

    /// ===============================
    /// ===== WithdrawOther Tests =====
    /// ===============================

    function testSweepExtraTokenIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.sweepExtraToken(address(0));
    }

    function testGovernanceCanSweepExtraToken() public {
        address extra = address(new MockToken("extra", "EXTR"));
        vm.prank(governance);
        vault.sweepExtraToken(extra);
    }

    function testStrategistCanSweepExtraToken() public {
        address extra = address(new MockToken("extra", "EXTR"));
        vm.prank(strategist);
        vault.sweepExtraToken(extra);
    }

    function testCantSweepWant() public {
        vm.prank(governance);
        vm.expectRevert("No want");
        vault.sweepExtraToken(WANT);
    }

    function testSweepExtraToken() public {
        MockToken extra = new MockToken("extra", "EXTR");
        extra.mint(address(vault), 100);

        vm.prank(governance);
        vault.sweepExtraToken(address(extra));

        assertEq(extra.balanceOf(address(vault)), 0);
        assertEq(extra.balanceOf(governance), 100);
    }

    /// =================================
    /// ===== WithdrawToVault Tests =====
    /// =================================

    function testWithdrawToVaultIsProtected() public {
        vm.expectRevert("onlyGovernanceOrStrategist");
        vault.withdrawToVault();
    }

    function testGovernanceCanWithdrawToVault() public {
        vm.prank(governance);
        vault.withdrawToVault();
    }

    function testStrategistCanWithdrawToVault() public {
        vm.prank(strategist);
        vault.withdrawToVault();
    }

    function testWithdrawToVault() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));

        depositChecked(amount);
        earnChecked();

        withdrawToVaultChecked();
    }

    /// ========================
    /// ===== Report Tests =====
    /// ========================

    function testReportHarvestIsProtected() public {
        vm.expectRevert("onlyStrategy");
        vault.reportHarvest(0);
    }

    function testStrategyCanReportHarvest() public {
        vm.prank(address(strategy));
        vault.reportHarvest(0);
    }

    function testReportHarvest() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositChecked(amount);

        reportHarvestChecked(1e18);
    }

    function testReportAdditionalTokenIsProtected() public {
        vm.expectRevert("onlyStrategy");
        vault.reportAdditionalToken(EMITS[0]);
    }

    function testCantReportWant() public {
        vm.prank(address(strategy));
        vm.expectRevert("No want");
        vault.reportAdditionalToken(WANT);
    }

    function testReportAdditionalToken() public {
        uint256 numRewards = EMITS.length;
        for (uint256 i; i < numRewards; ++i) {
            reportAdditionalTokenChecked(EMITS[i], 1e18, "EMITS[i]");
        }
    }

    /// =========================
    /// ===== Pausing Tests =====
    /// =========================

    function testPauseIsProtected() public {
        vm.expectRevert("onlyPausers");
        vault.pause();
    }

    function testGovernanceCanPause() public {
        vm.prank(governance);
        vault.pause();

        assertTrue(vault.paused());
    }

    function testGuardianCanPause() public {
        vm.prank(governance);
        vault.pause();

        assertTrue(vault.paused());
    }

    function testUnpauseIsProtected() public {
        vm.prank(governance);
        vault.pause();

        vm.expectRevert("onlyGovernance");
        vault.unpause();
    }

    function testGovernanceCanUnpause() public {
        vm.startPrank(governance);
        vault.pause();
        vault.unpause();

        assertFalse(vault.paused());
    }
}

/*
TODO:
- Do infinite approval instead of in prepareDeposit
- guestList ==> guestlist
- No upgradeable in test contract
- Generalize
- Add guestlist
- Add proxy
- EOA lock
- Comparator revert ==> test fail
- Add unchecked deposit, earn, harvest, withdraw etc.
- Unchecked deposit in earn tests etc.
- Helpers: deposit, depositAndEarn, depositAndEarnAndHarvest
- vm.expectEmit everywhere
- (no) Vault doesn't care about strategy.balanceOfWant()/strategy.balanceOfPool(). Maybe move that to strat tests?
- earn should check strategy.balanceOfWant()/strategy.balanceOfPool()
- More fuzzing? Fuzzing everywhere?
- Events to setter tests
- IERC20(WANT).bal... ==> AMOUNT_TO_MINT?

- Vault improvements:
  - Way to charge withdrawal fee without transferring want to vault?
  - Less asserts/gas improvements (maybe not in view funcs?)
  - Simplify share math if possible
  - Auth instead of access control
  - Time weight harvest amounts for calculating apr on-chain? (store accumulated vals)
  - reportHarvest automated? (what if balanceOfPool changes with harvest?)
  - Remove timestamp/bn from events
  - Loss reporting:
    - https://github.com/yearn/yearn-vaults/blob/main/contracts/Vault.vy#L1120-L1128
    - https://github.com/yearn/yearn-vaults/blob/main/contracts/Vault.vy#L1037-L1063
  - 2-step governance delegation
  - Fail harvest if balance is 0? Send everything to governance?
    Weighted split between governance/strategist?
    Force non-zero balance during deployment?

- Strategy improvements:
  - Take want from vault
  - Less asserts/gas improvements
  - BaseStrategy => Strategy
*/
