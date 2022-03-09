import time

from brownie import (
    MockStrategy,
    Vault,
    MockToken,
    TestVipCappedGuestListBbtcUpgradeable,
    accounts,
)

from helpers.constants import AddressZero
from rich.console import Console

console = Console()

from dotmap import DotMap
import pytest

performanceFeeGovernance = 1000
performanceFeeStrategist = 1000
withdrawalFee = 50
managementFee = 50

################# Token #################


@pytest.fixture
def token(dev, deployer):
    token = MockToken.deploy({"from": deployer})
    token.initialize([dev.address], [1000 * 10**18])
    return token


@pytest.fixture
def badger(dev, deployer):
    badger = MockToken.deploy({"from": deployer})
    badger.initialize([dev.address], [1000 * 10**18])
    return badger


#########################################

################# Actors #################

# Initializer and giver of tokens
@pytest.fixture
def dev():
    yield accounts[0]


@pytest.fixture
def deployer():
    yield accounts[1]


@pytest.fixture
def keeper():
    yield accounts[2]


@pytest.fixture
def strategist():
    yield accounts[3]


@pytest.fixture
def guardian():
    yield accounts[4]


@pytest.fixture
def governance():
    yield accounts[5]


@pytest.fixture
def proxyAdmin():
    yield accounts[6]


@pytest.fixture
def randomUser():
    yield accounts[8]


###########################################

################# Deploy #################
@pytest.fixture
def deployed_vault(
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
    return vault


@pytest.fixture
def deploy_complete(
    deployer, governance, keeper, guardian, randomUser, badgerTree, strategist
):

    want = MockToken.deploy({"from": deployer})
    want.initialize(
        [deployer.address, randomUser.address], [100 * 10**18, 100 * 10**18]
    )

    badger = MockToken.deploy({"from": deployer})
    badger.initialize(
        [deployer.address, randomUser.address], [100 * 10**18, 100 * 10**18]
    )

    # NOTE: change strategist
    vault = Vault.deploy({"from": deployer})
    vault.initialize(
        want,
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
    vault.setStrategist(strategist, {"from": governance})
    vault.setToEarnBps(10_000, {"from": governance})  ## Max earn bps so math is simpler
    # NOTE: Vault starts unpaused

    strategy = MockStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [want, badger])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(
        vault=vault,
        strategy=strategy,
        want=want,
        badger=badger,
        performanceFeeGovernance=performanceFeeGovernance,
        performanceFeeStrategist=performanceFeeStrategist,
        withdrawalFee=withdrawalFee,
    )


@pytest.fixture
def deployed_gueslist(
    deployed_vault,
    deployer,
    governance,
    proxyAdmin,
    keeper,
    guardian,
    strategist,
    token,
    badger,
):
    """
    Deploys TestVipCappedGuestListBbtcUpgradeable.sol for testing Guest List functionality
    """

    # NOTE: Change accordingly
    vaultAddr = deployed_vault.address
    merkleRoot = "0x1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a"
    userCap = 2e18
    totalCap = 50e18

    # Get deployer account from local keystore. Deployer must be the
    # vault's governance address in order to set its guestlist parameters.
    dev = deployer

    # Get actors
    governance = governance
    proxyAdmin = proxyAdmin

    assert governance != AddressZero
    assert proxyAdmin != AddressZero

    # Deploy guestlist
    guestlist = deploy_guestlist(dev, proxyAdmin, vaultAddr)

    # Set guestlist parameters
    guestlist.setUserDepositCap(userCap, {"from": dev})
    assert guestlist.userDepositCap() == userCap

    guestlist.setTotalDepositCap(totalCap, {"from": dev})
    assert guestlist.totalDepositCap() == totalCap

    # Transfers ownership of guestlist to Badger Governance
    guestlist.transferOwnership(governance, {"from": dev})
    assert guestlist.owner() == governance

    vault = deployed_vault

    vault.setStrategist(deployer, {"from": governance})
    # NOTE: Vault starts unpaused

    performanceFeeGovernance = 1000
    performanceFeeStrategist = 1000
    withdrawalFee = 50

    strategy = MockStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [token, badger])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(vault=vault, guestlist=guestlist, strategy=strategy)


def deploy_guestlist(dev, proxyAdmin, vaultAddr):
    guestlist = TestVipCappedGuestListBbtcUpgradeable.deploy({"from": dev})

    guestlist.initialize(vaultAddr, {"from": dev})

    # console.print("[green] Using Guestlist in conftest.py/functional")
    console.print("[green]Guestlist was deployed at: [/green]", guestlist.address)

    return guestlist


#############################################
