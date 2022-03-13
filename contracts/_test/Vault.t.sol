// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ApproxUint256, ApproxUint256Utils} from "./utils/ApproxUint256.sol";
import {DSTest2} from "./utils/DSTest2.sol";
import {ERC20Utils} from "./utils/ERC20Utils.sol";
import {SnapshotComparator} from "./utils/Snapshot.sol";
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
    using ApproxUint256Utils for ApproxUint256;

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

    event Harvest(uint256 harvested, uint256 indexed blockNumber);

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

    function testWithdrawWithLossyStrategy(uint256 sharesToWithdraw) public {
        uint256 amount = IERC20(WANT).balanceOf(address(this));
        uint256 shares = depositChecked(amount);
        earnChecked();

        vm.prank(governance);
        strategy.setLossBps(10);

        sharesToWithdraw = bound(sharesToWithdraw, 1, shares);
        withdrawChecked(sharesToWithdraw);
    }

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
        vm.expectRevert("No want");
        vm.prank(governance);
        vault.sweepExtraToken(address(WANT));
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

        comparator.assertNegDiff("want.balanceOf(from)", _amount);
        comparator.assertDiff("want.balanceOf(vault)", _amount);
        comparator.assertDiff("vault.balanceOf(to)", expectedShares);

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
            "want.balanceOf(strategy)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(strategy))
        );
        comparator.addCall(
            "strategy.balanceOfPool()",
            address(strategy),
            abi.encodeWithSignature("balanceOfPool()")
        );

        uint256 expectedEarn = (IERC20(WANT).balanceOf(address(vault)) *
            vault.toEarnBps()) / MAX_BPS;

        comparator.snapPrev();
        vm.prank(keeper);

        vault.earn();

        comparator.snapCurr();

        comparator.assertNegDiff("want.balanceOf(vault)", expectedEarn);

        // TODO: Maybe relax this for loss making strategies?
        assertEq(
            comparator.diff("want.balanceOf(strategy)") +
                comparator.diff("strategy.balanceOfPool()"),
            expectedEarn
        );
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
            "want.balanceOf(strategy)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(strategy))
        );
        comparator.addCall(
            "strategy.balanceOfPool()",
            address(strategy),
            abi.encodeWithSignature("balanceOfPool()")
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

        ApproxUint256 memory expectedAmountWithoutFee = ApproxUint256RelBps(
            (_shares * comparator.prev("vault.getPricePerFullShare()")) / 1e18,
            10
        );

        ApproxUint256 memory withdrawalFee = expectedAmountWithoutFee
            .mul(vault.withdrawalFee())
            .div(MAX_BPS);

        // TODO: management fee
        ApproxUint256 memory fee = withdrawalFee;
        ApproxUint256 memory feeInShares = fee.mul(1e18).div(
            comparator.prev("vault.getPricePerFullShare()")
        );

        ApproxUint256 memory expectedAmount = expectedAmountWithoutFee.sub(
            fee,
            true
        );

        comparator.assertNegDiff("vault.balanceOf(from)", _shares);
        comparator.assertDiff("want.balanceOf(from)", expectedAmount);
        comparator.assertDiff("vault.balanceOf(treasury)", feeInShares);

        if (
            expectedAmountWithoutFee.le(
                comparator.prev("want.balanceOf(vault)")
            )
        ) {
            comparator.assertNegDiff("want.balanceOf(vault)", expectedAmount);
        } else {
            ApproxUint256 memory required = expectedAmountWithoutFee.sub(
                comparator.prev("want.balanceOf(vault)")
            );
            assertEq(comparator.curr("want.balanceOf(vault)"), fee);

            if (required.le(comparator.prev("want.balanceOf(strategy)"))) {
                comparator.assertNegDiff("want.balanceOf(strategy)", required);
            } else {
                required = required.sub(
                    comparator.prev("want.balanceOf(strategy)")
                );

                assertEq(comparator.curr("want.balanceOf(strategy)"), 0);
                comparator.assertNegDiff("strategy.balanceOfPool()", required);
            }
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
        emit Harvest(0, block.number);

        // TODO: Return value?
        strategy.harvest();

        vm.stopPrank();

        comparator.snapCurr();

        // assertEq(harvested, 0);

        comparator.assertEq("vault.getPricePerFullShare()");
        comparator.assertEq("strategy.balanceOf()");

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

    function withdrawToVaultChecked() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "want.balanceOf(strategy)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(strategy))
        );

        comparator.snapPrev();
        vm.prank(governance);

        vault.withdrawToVault();

        comparator.snapCurr();

        assertEq(comparator.curr("want.balanceOf(strategy)"), 0);
        comparator.assertDiff(
            "want.balanceOf(vault)",
            comparator.prev("want.balanceOf(strategy)")
        );
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
- Unchecked deposit in earn tests etc.

- Vault improvements:
 - Way to charge withdrawal fee without transferring want to vault?
 - Less checks/gas improvements
 - Simplify share math if possible
 - Auth instead of access control

- Strategy improvements:
 - Take want from vault
*/
