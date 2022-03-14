// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IntervalUint256, IntervalUint256Utils} from "./utils/IntervalUint256.sol";
import {DSTest2} from "./utils/DSTest2.sol";
import {ERC20Utils} from "./utils/ERC20Utils.sol";
import {SnapshotComparator} from "./utils/SnapshotUtils.sol";
import {Vault} from "../Vault.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {MockToken} from "../mocks/MockToken.sol";

abstract contract Config {
    address internal immutable WANT = address(new MockToken("want", "WANT"));
    address[1] internal EMITS = [address(new MockToken("emit", "EMIT"))];

    uint256 public constant PERFORMANCE_FEE_GOVERNANCE = 1_500;
    uint256 public constant PERFORMANCE_FEE_STRATEGIST = 0;
    uint256 public constant WITHDRAWAL_FEE = 10;
    uint256 public constant MANAGEMENT_FEE = 2;
}

abstract contract Utils {
    function getAddress(string memory _name)
        internal
        pure
        returns (address addr_)
    {
        addr_ = address(uint160(uint256(keccak256(bytes(_name)))));
    }
}

contract VaultTest is DSTest2, stdCheats, Config, Utils {
    using IntervalUint256Utils for IntervalUint256;

    // ==============
    // ===== Vm =====
    // ==============

    Vm constant vm = Vm(HEVM_ADDRESS);

    ERC20Utils immutable erc20utils = new ERC20Utils();
    SnapshotComparator comparator;

    // =====================
    // ===== Constants =====
    // =====================

    address immutable governance = getAddress("governance");
    address immutable strategist = getAddress("strategist");
    address immutable guardian = getAddress("guardian");
    address immutable keeper = getAddress("keeper");
    address immutable treasury = getAddress("treasury");
    address immutable badgerTree = getAddress("badgerTree");

    address immutable rando = getAddress("rando");

    uint256 constant MAX_BPS = 10_000;
    uint256 constant AMOUNT_TO_MINT = 10e18;

    // =================
    // ===== State =====
    // =================

    Vault vault = new Vault();
    MockStrategy strategy = new MockStrategy();

    // ==================
    // ===== Events =====
    // ==================

    event Harvested(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event PerformanceFeeGovernance(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event PerformanceFeeStrategist(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public {
        vm.label(address(this), "this");

        vm.label(WANT, IERC20Metadata(WANT).symbol());
        vm.label(governance, "governance");
        vm.label(keeper, "keeper");
        vm.label(guardian, "guardian");
        vm.label(treasury, "treasury");
        vm.label(strategist, "strategist");
        vm.label(badgerTree, "badgerTree");

        vm.label(rando, "rando");

        vm.label(address(vault), "vault");
        vm.label(address(strategy), "strategy");

        vault.initialize(
            WANT,
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

        uint256 numRewards = EMITS.length;
        address[] memory rewards = new address[](numRewards);
        for (uint256 i; i < numRewards; ++i) {
            rewards[i] = EMITS[i];
            vm.label(EMITS[i], IERC20Metadata(EMITS[i]).symbol());
        }
        strategy.initialize(address(vault), rewards);

        vm.prank(governance);
        vault.setStrategy(address(strategy));

        erc20utils.forceMint(WANT, AMOUNT_TO_MINT);

        comparator = new SnapshotComparator();
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
        uint256 amount = IERC20(WANT).balanceOf(address(this));

        depositChecked(amount);
        earnChecked();
    }

    function testEarnFailsWhenStrategyPaused() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositChecked(amount);

        vm.startPrank(governance);
        strategy.pause();

        vm.expectRevert("Pausable: paused");
        vault.earn();
    }

    function testEarnFailsWhenDepositsArePaused() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositChecked(amount);

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
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        uint256 shares = depositChecked(amount);
        earnChecked();

        sharesToWithdraw = bound(sharesToWithdraw, 1, shares);
        withdrawChecked(sharesToWithdraw);
    }

    function testWithdrawBeforeEarn() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        uint256 shares = depositChecked(amount);
        withdrawChecked(shares);
    }

    function testWithdrawTwice() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        uint256 shares = depositChecked(amount);
        earnChecked();

        withdrawChecked(shares / 2);
        withdrawChecked(shares - shares / 2);
    }

    function testWithdrawAll() public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        depositChecked(amount);
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
            reportAdditionalTokenChecked(EMITS[i], 1e18);
        }
    }

    /// ==========================
    /// ===== Strategy Tests =====
    /// ==========================

    // ============================
    // ===== Deployment Tests =====
    // ============================

    function testStrategyVaultIsSetProperly() public {
        assertEq(strategy.vault(), address(vault));
    }

    function testStrategyGovernanceIsSetProperly() public {
        assertEq(strategy.governance(), governance);
    }

    function testStrategyKeeperIsSetProperly() public {
        assertEq(strategy.keeper(), keeper);
    }

    function testStrategyGuardianIsSetProperly() public {
        assertEq(strategy.guardian(), guardian);
    }

    function testWithdrawalMaxDeviationThresholdIsSetProperly() public {
        assertEq(strategy.withdrawalMaxDeviationThreshold(), 50);
    }

    function testStrategyMaxBpsIsSetProperly() public {
        assertEq(strategy.MAX_BPS(), 10_000);
    }

    function testStrategyInitializeFailsWhenVaultIsAddressZero() public {
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

    /// ============================
    /// ===== Internal helpers =====
    /// ============================

    function prepareDepositFor(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        comparator.addCall(
            "want.balanceOf(from)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "vault.balanceOf(to)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", _to)
        );
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );

        comparator.snapPrev();

        vm.startPrank(_from, _from);
        IERC20(WANT).approve(address(vault), _amount);
    }

    function postDeposit(uint256 _amount) internal returns (uint256 shares_) {
        vm.stopPrank();

        comparator.snapCurr();

        uint256 expectedShares = (_amount * 1e18) /
            comparator.prev("vault.getPricePerFullShare()");

        assertEq(comparator.negDiff("want.balanceOf(from)"), _amount);
        assertEq(comparator.diff("want.balanceOf(vault)"), _amount);
        assertEq(comparator.diff("vault.balanceOf(to)"), expectedShares);

        shares_ = comparator.diff("vault.balanceOf(to)");
    }

    function depositCheckedFrom(address _from, uint256 _amount)
        internal
        returns (uint256 shares_)
    {
        prepareDepositFor(_from, _from, _amount);
        vault.deposit(_amount);
        shares_ = postDeposit(_amount);
    }

    function depositChecked(uint256 _amount)
        internal
        returns (uint256 shares_)
    {
        shares_ = depositCheckedFrom(address(this), _amount);
    }

    function depositForCheckedFrom(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256 shares_) {
        prepareDepositFor(_from, _to, _amount);
        vault.depositFor(_to, _amount);
        shares_ = postDeposit(_amount);
    }

    function depositForChecked(uint256 _amount, address _to)
        internal
        returns (uint256 shares_)
    {
        shares_ = depositForCheckedFrom(address(this), _to, _amount);
    }

    function depositAllCheckedFrom(address _from)
        internal
        returns (uint256 shares_)
    {
        uint256 amount = IERC20(WANT).balanceOf(_from);
        prepareDepositFor(_from, _from, amount);
        vault.depositAll();
        shares_ = postDeposit(amount);
    }

    function depositAllChecked() internal returns (uint256 shares_) {
        shares_ = depositAllCheckedFrom(address(this));
    }

    function earnChecked() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );

        uint256 expectedEarn = (IERC20(WANT).balanceOf(address(vault)) *
            vault.toEarnBps()) / MAX_BPS;

        comparator.snapPrev();
        vm.prank(keeper);

        vault.earn();

        comparator.snapCurr();

        assertEq(comparator.negDiff("want.balanceOf(vault)"), expectedEarn);

        // TODO: Maybe relax this for loss making strategies?
        assertEq(comparator.diff("strategy.balanceOf()"), expectedEarn);
    }

    function prepareWithdraw(address _from) internal {
        comparator.addCall(
            "vault.balanceOf(from)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "vault.balanceOf(treasury)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            "want.balanceOf(from)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );

        comparator.snapPrev();
        vm.prank(_from, _from);
    }

    function postWithdraw(uint256 _shares) internal returns (uint256 amount_) {
        comparator.snapCurr();

        uint256 amountZeroFee = (_shares *
            comparator.prev("vault.getPricePerFullShare()")) / 1e18;

        assertEq(comparator.negDiff("vault.balanceOf(from)"), _shares);

        if (amountZeroFee <= comparator.prev("want.balanceOf(vault)")) {
            uint256 withdrawalFee = (amountZeroFee * WITHDRAWAL_FEE) / MAX_BPS;

            uint256 withdrawalFeeInShares = (withdrawalFee * 1e18) /
                comparator.prev("vault.getPricePerFullShare()");

            uint256 amount = amountZeroFee - withdrawalFee;

            assertEq(comparator.negDiff("want.balanceOf(vault)"), amount);
            assertEq(comparator.diff("want.balanceOf(from)"), amount);
            assertEq(
                comparator.diff("vault.balanceOf(treasury)"),
                withdrawalFeeInShares
            );
        } else {
            // TODO: Probably doesn't make sense since loss isn't handled properly in strat
            IntervalUint256 memory amountFromStrategyInterval = IntervalUint256Utils
                .fromMaxAndTolBps(
                    amountZeroFee - comparator.prev("want.balanceOf(vault)"),
                    10 // TODO: No magic
                );

            IntervalUint256
                memory amountZeroFeeInterval = amountFromStrategyInterval.add(
                    comparator.prev("want.balanceOf(vault)")
                );

            IntervalUint256 memory withdrawalFee = amountZeroFeeInterval
                .mul(WITHDRAWAL_FEE)
                .div(MAX_BPS);

            IntervalUint256 memory withdrawalFeeInShares = withdrawalFee
                .mul(1e18)
                .div(comparator.prev("vault.getPricePerFullShare()"));

            assertEq(comparator.curr("want.balanceOf(vault)"), withdrawalFee);
            assertEq(
                comparator.diff("want.balanceOf(from)"),
                amountZeroFeeInterval.sub(withdrawalFee, true)
            );
            assertEq(
                comparator.diff("vault.balanceOf(treasury)"),
                withdrawalFeeInShares
            );
            assertEq(
                comparator.negDiff("strategy.balanceOf()"),
                amountFromStrategyInterval
            );
        }

        amount_ = comparator.diff("want.balanceOf(from)");
    }

    function withdrawCheckedFrom(address _from, uint256 _shares)
        internal
        returns (uint256 amount_)
    {
        prepareWithdraw(_from);
        vault.withdraw(_shares);
        amount_ = postWithdraw(_shares);
    }

    function withdrawChecked(uint256 _shares)
        internal
        returns (uint256 amount_)
    {
        amount_ = withdrawCheckedFrom(address(this), _shares);
    }

    function withdrawAllCheckedFrom(address _from)
        internal
        returns (uint256 amount_)
    {
        prepareWithdraw(_from);
        uint256 shares = vault.balanceOf(_from);
        vault.withdrawAll();
        amount_ = postWithdraw(shares);
    }

    function withdrawAllChecked() internal returns (uint256 amount_) {
        amount_ = withdrawAllCheckedFrom(address(this));
    }

    function withdrawToVaultChecked() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );

        comparator.snapPrev();
        vm.prank(governance);

        vault.withdrawToVault();

        comparator.snapCurr();

        assertEq(comparator.curr("strategy.balanceOf()"), 0);
        // TODO: Maybe relax this for loss making strategies?
        assertEq(
            comparator.diff("want.balanceOf(vault)"),
            comparator.prev("strategy.balanceOf()")
        );
    }

    function reportHarvestChecked(uint256 _amount) internal {
        comparator.addCall(
            "vault.balanceOf(treasury)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            "vault.balanceOf(strategist)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", strategist)
        );
        comparator.addCall(
            "vault.balance()",
            address(vault),
            abi.encodeWithSignature("balance()")
        );
        comparator.addCall(
            "vault.lastHarvestAmount()",
            address(vault),
            abi.encodeWithSignature("lastHarvestAmount()")
        );
        comparator.addCall(
            "vault.assetsAtLastHarvest()",
            address(vault),
            abi.encodeWithSignature("assetsAtLastHarvest()")
        );
        comparator.addCall(
            "vault.lastHarvestedAt()",
            address(vault),
            abi.encodeWithSignature("lastHarvestedAt()")
        );
        comparator.addCall(
            "vault.lifeTimeEarned()",
            address(vault),
            abi.encodeWithSignature("lifeTimeEarned()")
        );

        comparator.snapPrev();

        erc20utils.forceMintTo(address(vault), WANT, _amount);

        vm.expectEmit(true, true, false, true);
        emit Harvested(WANT, _amount, block.number, block.timestamp);

        vm.prank(address(strategy));
        vault.reportHarvest(_amount);

        comparator.snapCurr();

        // TODO: management fee
        uint256 governanceFee = (_amount * PERFORMANCE_FEE_GOVERNANCE) /
            MAX_BPS;
        uint256 strategistFee = (_amount * PERFORMANCE_FEE_STRATEGIST) /
            MAX_BPS;

        assertEq(
            comparator.diff("vault.balanceOf(treasury)"),
            (governanceFee * 1e18) /
                comparator.curr("vault.getPricePerFullShare()")
        );
        assertEq(
            comparator.diff("vault.balanceOf(strategist)"),
            (strategistFee * 1e18) /
                comparator.curr("vault.getPricePerFullShare()")
        );
        assertEq(comparator.curr("vault.lastHarvestAmount()"), _amount);
        assertEq(
            comparator.curr("vault.assetsAtLastHarvest()"),
            comparator.prev("vault.balance()")
        );
        assertEq(comparator.curr("vault.lastHarvestedAt()"), block.timestamp);
        assertEq(comparator.diff("vault.lifeTimeEarned()"), _amount);
    }

    function reportAdditionalTokenChecked(address _token, uint256 _amount)
        internal
    {
        comparator.addCall(
            "token.balanceOf(treasury)",
            _token,
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            "token.balanceOf(strategist)",
            _token,
            abi.encodeWithSignature("balanceOf(address)", strategist)
        );
        comparator.addCall(
            "token.balanceOf(badgerTree)",
            _token,
            abi.encodeWithSignature("balanceOf(address)", badgerTree)
        );
        comparator.addCall(
            "vault.additionalTokensEarned(token)",
            address(vault),
            abi.encodeWithSignature("additionalTokensEarned(address)", _token)
        );
        comparator.addCall(
            "vault.lastAdditionalTokenAmount(token)",
            address(vault),
            abi.encodeWithSignature(
                "lastAdditionalTokenAmount(address)",
                _token
            )
        );

        // TODO: management fee
        uint256 governanceFee = (_amount * PERFORMANCE_FEE_GOVERNANCE) /
            MAX_BPS;
        uint256 strategistFee = (_amount * PERFORMANCE_FEE_STRATEGIST) /
            MAX_BPS;

        comparator.snapPrev();

        erc20utils.forceMintTo(address(vault), _token, _amount);

        vm.prank(address(strategy));

        vm.expectEmit(true, true, false, true);
        emit TreeDistribution(
            _token,
            _amount - governanceFee - strategistFee,
            block.number,
            block.timestamp
        );
        vault.reportAdditionalToken(_token);

        comparator.snapCurr();

        assertEq(
            comparator.curr("vault.lastAdditionalTokenAmount(token)"),
            _amount
        );
        assertEq(
            comparator.diff("vault.additionalTokensEarned(token)"),
            _amount
        );
        assertEq(comparator.diff("token.balanceOf(treasury)"), governanceFee);
        assertEq(comparator.diff("token.balanceOf(strategist)"), strategistFee);
        assertEq(
            comparator.diff("token.balanceOf(badgerTree)"),
            _amount - governanceFee - strategistFee
        );
    }

    // TODO: Move to strategy tests
    function harvestChecked() internal {
        uint256 numRewards = EMITS.length;
        uint256 performanceFeeGovernance = vault.performanceFeeGovernance();
        uint256 performanceFeeStrategist = vault.performanceFeeStrategist();

        // TODO: There has to be a better way to do this
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );

        for (uint256 i; i < numRewards; ++i) {
            string memory name = IERC20Metadata(EMITS[i]).name();
            comparator.addCall(
                string.concat(name, ".balanceOf(treasury)"),
                address(EMITS[i]),
                abi.encodeWithSignature("balanceOf(address)", treasury)
            );
            comparator.addCall(
                string.concat(name, ".balanceOf(strategist)"),
                address(EMITS[i]),
                abi.encodeWithSignature("balanceOf(address)", strategist)
            );
            comparator.addCall(
                string.concat(name, ".balanceOf(badgerTree)"),
                address(EMITS[i]),
                abi.encodeWithSignature("balanceOf(address)", badgerTree)
            );
        }

        comparator.snapPrev();
        vm.startPrank(keeper);

        for (uint256 i; i < numRewards; ++i) {
            if (performanceFeeGovernance > 0) {
                vm.expectEmit(true, true, true, false); // Not checking amount
                emit PerformanceFeeGovernance(
                    treasury,
                    address(EMITS[i]),
                    0, // dummy
                    block.number,
                    block.timestamp
                );
            }

            if (performanceFeeStrategist > 0) {
                vm.expectEmit(true, true, true, false); // Not checking amount
                emit PerformanceFeeStrategist(
                    strategist,
                    address(EMITS[i]),
                    0, // dummy
                    block.number,
                    block.timestamp
                );
            }
        }

        vm.expectEmit(true, false, false, true);
        emit Harvested(WANT, 0, block.number, block.timestamp);

        // TODO: Return value?
        strategy.harvest();

        vm.stopPrank();

        comparator.snapCurr();

        // assertEq(harvested, 0);

        assertZe(comparator.diff("vault.getPricePerFullShare()"));
        assertZe(comparator.diff("strategy.balanceOf()"));

        for (uint256 i; i < numRewards; ++i) {
            string memory name = IERC20Metadata(EMITS[i]).name();
            uint256 deltaRewardBalanceOfTreasury = comparator.diff(
                string.concat(name, ".balanceOf(treasury)")
            );
            uint256 deltaRewardBalanceOfStrategist = comparator.diff(
                string.concat(name, ".balanceOf(strategist)")
            );
            uint256 deltaRewardBalanceOfBadgerTree = comparator.diff(
                string.concat(name, ".balanceOf(badgerTree)")
            );

            uint256 rewardEmitted = deltaRewardBalanceOfTreasury +
                deltaRewardBalanceOfStrategist +
                deltaRewardBalanceOfBadgerTree;

            uint256 rewardGovernanceFee = (rewardEmitted *
                performanceFeeGovernance) / MAX_BPS;
            uint256 rewardStrategistFee = (rewardEmitted *
                performanceFeeStrategist) / MAX_BPS;

            assertEq(deltaRewardBalanceOfTreasury, rewardGovernanceFee);
            assertEq(deltaRewardBalanceOfStrategist, rewardStrategistFee);
            assertEq(
                deltaRewardBalanceOfBadgerTree,
                rewardEmitted - rewardGovernanceFee - rewardStrategistFee
            );
        }
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
- Vault doesn't care about strategy.balanceOfWant()/strategy.balanceOfPool(). Maybe move that to strat tests?
- More fuzzing? Fuzzing everywhere?

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

- Strategy improvements:
  - Take want from vault
  - Less asserts/gas improvements
*/
