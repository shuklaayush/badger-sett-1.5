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

    /*
def test_setMaxPerformanceFee(deployed_vault, governance, strategist, randomUser):

    # setting maxPeformanceFees > MAX should fail
    with brownie.reverts("performanceFeeStrategist too high"):
        deployed_vault.setMaxPerformanceFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting min
    deployed_vault.setMaxPerformanceFee(3_000, {"from": governance})

    assert deployed_vault.maxPerformanceFee() == 3_000

    # setting maxPeformanceFees from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxPerformanceFee(1_000, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxPerformanceFee(1_000, {"from": strategist})


def test_setMaxWithdrawalFee(deployed_vault, governance, strategist, randomUser):

    # setting maxWithdrawalFee > MAX should fail
    with brownie.reverts("withdrawalFee too high"):
        deployed_vault.setMaxWithdrawalFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting setMaxWithdrawalFee
    deployed_vault.setMaxWithdrawalFee(100, {"from": governance})

    assert deployed_vault.maxWithdrawalFee() == 100

    # setting setMaxWithdrawalFee from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxWithdrawalFee(100, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxWithdrawalFee(100, {"from": strategist})


def test_setMaxManagementFee(deployed_vault, governance, strategist, randomUser):

    # setting maxManagementFee > MAX should fail
    with brownie.reverts("managementFee too high"):
        deployed_vault.setMaxManagementFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting setMaxWithdrawalFee
    deployed_vault.setMaxManagementFee(150, {"from": governance})

    assert deployed_vault.maxManagementFee() == 150

    # setting setMaxWithdrawalFee from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxManagementFee(200, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxManagementFee(200, {"from": strategist})


def test_setManagementFee(deployed_vault, governance, strategist, randomUser):

    # setting managementFee
    deployed_vault.setManagementFee(100, {"from": governance})

    assert deployed_vault.managementFee() == 100

    # setting managementFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setManagementFee(5_000, {"from": randomUser})

    # setting more that maxManagementFee should fail
    with brownie.reverts("Excessive management fee"):
        deployed_vault.setManagementFee(
            2 * deployed_vault.maxManagementFee(), {"from": strategist}
        )


def test_setWithdrawalFee(deployed_vault, governance, strategist, randomUser):

    withdrawalFee = 100

    # withdrawalFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setWithdrawalFee(withdrawalFee, {"from": randomUser})

    # setting withdrawalFee
    deployed_vault.setWithdrawalFee(withdrawalFee, {"from": governance})

    assert deployed_vault.withdrawalFee() == withdrawalFee

    # setting more that maxWithdrawalFee should fail
    with brownie.reverts("Excessive withdrawal fee"):
        deployed_vault.setWithdrawalFee(
            2 * deployed_vault.maxWithdrawalFee(), {"from": strategist}
        )


def test_setPerformanceFeeStrategist(
    deployed_vault, governance, strategist, randomUser
):

    performanceFeeStrategist = 2_000  # increasing fees to compensate good strategist.

    # setPerformanceFeeStrategist from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setPerformanceFeeStrategist(
            performanceFeeStrategist, {"from": randomUser}
        )

    # setPerformanceFeeStrategist from governance
    deployed_vault.setPerformanceFeeStrategist(
        performanceFeeStrategist, {"from": governance}
    )

    # setPerformanceFeeStrategist from strategist
    deployed_vault.setPerformanceFeeStrategist(
        performanceFeeStrategist, {"from": strategist}
    )

    assert deployed_vault.performanceFeeStrategist() == performanceFeeStrategist

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("Excessive strategist performance fee"):
        deployed_vault.setPerformanceFeeStrategist(
            2 * deployed_vault.maxPerformanceFee(), {"from": strategist}
        )


def test_setPerformanceFeeGovernance(
    deployed_vault, governance, strategist, randomUser
):

    performanceFeeGovernance = 2_000

    # setPerformanceFeeGovernance from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setPerformanceFeeGovernance(
            performanceFeeGovernance, {"from": randomUser}
        )

    # setPerformanceFeeGovernance from governance
    deployed_vault.setPerformanceFeeGovernance(
        performanceFeeGovernance, {"from": governance}
    )

    # setPerformanceFeeGovernance from strategist
    deployed_vault.setPerformanceFeeGovernance(
        performanceFeeGovernance, {"from": strategist}
    )

    assert deployed_vault.performanceFeeGovernance() == performanceFeeGovernance

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("Excessive governance performance fee"):
        deployed_vault.setPerformanceFeeGovernance(
            2 * deployed_vault.maxPerformanceFee(), {"from": strategist}
        )


def test_config_pause_unpause(deployed_vault, governance, strategist, randomUser):

    # Pause Vault
    deployed_vault.pause({"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setStrategy(randomUser, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setGuestList(randomUser, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setToEarnBps(100, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setManagementFee(1_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeGovernance(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeStrategist(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setWithdrawalFee(100, {"from": governance})

    # unpause Vault, now we should be able to set everything
    deployed_vault.unpause({"from": governance})
    deployed_vault.setStrategy(randomUser, {"from": governance})
    deployed_vault.setGuestList(randomUser, {"from": governance})
    deployed_vault.setToEarnBps(100, {"from": governance})
    deployed_vault.setGuardian(randomUser, {"from": governance})
    deployed_vault.setMaxPerformanceFee(2_000, {"from": governance})
    deployed_vault.setMaxWithdrawalFee(50, {"from": governance})
    deployed_vault.setMaxManagementFee(150, {"from": governance})
    deployed_vault.setManagementFee(150, {"from": strategist})
    deployed_vault.setPerformanceFeeGovernance(2_000, {"from": strategist})
    deployed_vault.setPerformanceFeeStrategist(2_000, {"from": strategist})
    deployed_vault.setWithdrawalFee(50, {"from": strategist})

    with brownie.reverts("Pausable: not paused"):
        deployed_vault.unpause({"from": governance})
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
