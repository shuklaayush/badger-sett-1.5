from brownie import (
    DemoStrategy,
    Vault,
    MockToken,
    accounts
)
from dotmap import DotMap
import pytest


@pytest.fixture
def deployed():
    """
    Deploys, vault and test strat and wires them up.
    """
    deployer = accounts[1]

    strategist = deployer
    keeper = deployer
    guardian = deployer

    governance = accounts[2]

    token = MockToken.deploy({"from": deployer})
    token.initialize([deployer.address], [100*10**18])
    want = token

    vault = Vault.deploy({"from": deployer})
    vault.initialize(
      token, governance, keeper, guardian, False, "", ""
    )
    vault.setStrategist(deployer, {"from": governance})
    # NOTE: Vault starts unpaused

    strategy = DemoStrategy.deploy({"from": deployer})
    strategy.initialize(
      governance, strategist, vault, keeper, guardian, [token], [1000, 1000, 50]
    )
    # NOTE: Strategy starts unpaused

    vault.setStrategy(strategy, {"from": governance})

    return DotMap(
      deployer=deployer,
      vault=vault,
      strategy=strategy,
      want=want,
    )

## Contracts ##
@pytest.fixture
def vault(deployed):
    return deployed.vault


@pytest.fixture
def strategy(deployed):
    return deployed.strategy


## Tokens ##
@pytest.fixture
def want(deployed):
    return deployed.want


@pytest.fixture
def tokens(deployed):
    return [deployed.want]


## Accounts ##
@pytest.fixture
def deployer(deployed):
    return deployed.deployer


@pytest.fixture
def strategist(strategy):
    return accounts.at(strategy.strategist(), force=True)


@pytest.fixture
def settKeeper(vault):
    return accounts.at(vault.keeper(), force=True)


@pytest.fixture
def strategyKeeper(strategy):
    return accounts.at(strategy.keeper(), force=True)


## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass
