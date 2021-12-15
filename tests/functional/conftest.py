import time

from brownie import (
    DemoStrategy,
    Vault,
    MockToken,
    AdminUpgradeabilityProxy,
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
def token(badger, deployer):
    token = MockToken.deploy({"from": deployer})
    token.initialize([badger.address], [1000 * 10 ** 18])
    return token


#########################################

################# Actors #################

# Initializer and giver of tokens
@pytest.fixture
def badger():
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
def deployed_vault(deployer, governance, keeper, guardian, strategist, badgerTree, token):
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

    token = MockToken.deploy({"from": deployer})
    token.initialize(
        [deployer.address, randomUser.address], [100 * 10 ** 18, 100 * 10 ** 18]
    )
    want = token

    # NOTE: change strategist
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
    vault.setStrategist(strategist, {"from": governance})
    # NOTE: Vault starts unpaused

    strategy = DemoStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [token])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(
        vault=vault,
        strategy=strategy,
        want=want,
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

    strategy = DemoStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [token])
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(vault=vault, guestlist=guestlist, strategy=strategy)


def deploy_guestlist(dev, proxyAdmin, vaultAddr):

    guestlist_logic = TestVipCappedGuestListBbtcUpgradeable.deploy({"from": dev})

    # Initializing arguments
    args = [vaultAddr]

    guestlist_proxy = AdminUpgradeabilityProxy.deploy(
        guestlist_logic,
        proxyAdmin,
        guestlist_logic.initialize.encode_input(*args),
        {"from": dev},
    )
    time.sleep(1)

    ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(guestlist_proxy)
    guestlist_proxy = TestVipCappedGuestListBbtcUpgradeable.at(guestlist_proxy.address)

    # console.print("[green] Using Guestlist in conftest.py/functional")
    console.print("[green]Guestlist was deployed at: [/green]", guestlist_proxy.address)

    return guestlist_proxy


#############################################
