// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {DSTest} from "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {ERC20Utils} from "./utils/ERC20Utils.sol";
import {MulticallUtils} from "./utils/MulticallUtils.sol";
import {SnapshotComparator} from "./utils/Snapshot.sol";

import {Vault} from "../Vault.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {MockToken} from "../mocks/MockToken.sol";

abstract contract Config is MulticallUtils {
    MockToken internal immutable WANT = new MockToken();
    MockToken internal immutable EXTRA = new MockToken();

    uint256 public constant PERFORMANCE_FEE_GOVERNANCE = 1_500;
    uint256 public constant PERFORMANCE_FEE_STRATEGIST = 0;
    uint256 public constant WITHDRAWAL_FEE = 10;
    uint256 public constant MANAGEMENT_FEE = 2;

    address internal immutable MULTICALL = address(0);
}

abstract contract Utils {
    function getAddress(string memory _name) internal pure returns (address addr_) {
        addr_ = address(uint160(uint256(keccak256(bytes(_name)))));
    }
}

contract VaultTest is DSTest, stdCheats, Config, Utils {
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

    event TreeDistribution(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);
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
        vault.initialize(
            address(WANT),
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [PERFORMANCE_FEE_GOVERNANCE, PERFORMANCE_FEE_STRATEGIST, WITHDRAWAL_FEE, MANAGEMENT_FEE]
        );

        strategy.initialize(address(vault), [address(WANT), address(EXTRA)]);

        vm.prank(governance);
        vault.setStrategy(address(strategy));

        erc20utils.forceMint(address(WANT), AMOUNT_TO_MINT);

        comparator = new SnapshotComparator(MULTICALL);
    }

    // ======================
    // ===== Unit Tests =====
    // ======================

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

    /*
def test_vault_deployment(
    deployer, governance, keeper, guardian, strategist, badgerTree, token
):
    vault = Vault.deploy({"from": deployer})
    vault.initialize(
        token,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
        "",
        "",
        [
            performanceFeeGovernance,
            performanceFeeStrategist,
            withdrawalFee,
            managementFee,
        ],
    )

    # Addresses
    assert vault.governance() == governance
    assert vault.keeper() == keeper
    assert vault.guardian() == guardian
    assert vault.token() == token
    assert vault.treasury() == governance

    # Params
    assert vault.toEarnBps() == 9_500
    assert vault.performanceFeeGovernance() == performanceFeeGovernance
    assert vault.performanceFeeStrategist() == performanceFeeStrategist
    assert vault.withdrawalFee() == withdrawalFee
    assert vault.managementFee() == managementFee
    assert vault.MAX_BPS() == 10_000
    assert vault.maxPerformanceFee() == 3_000
    assert vault.maxWithdrawalFee() == 200
    assert vault.maxManagementFee() == 200


def test_vault_deployment_badArgument(
    deployer, governance, keeper, guardian, strategist, badgerTree, token
):
    vault = Vault.deploy({"from": deployer})
    default_address_args = [
        token,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
    ]

    for i in range(len(default_address_args)):
        address_args = [
            default_address_args[j] if j != i else AddressZero
            for j in range(len(default_address_args))
        ]

        with brownie.reverts():
            vault.initialize(
                *address_args,
                "",
                "",
                [
                    performanceFeeGovernance,
                    performanceFeeStrategist,
                    withdrawalFee,
                    managementFee,
                ],
            )

*/
}

/*
TODO:
- guestList ==> guestlist
- No upgradeable in test contract
- Generalize
- Add guestlist
- Add proxy
- EOA lock
*/
