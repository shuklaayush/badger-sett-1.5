import brownie
from brownie import (
    Vault,
    DemoStrategy
)

from helpers.constants import AddressZero

# Test's strategy's deployment
def test_strategy_deployment(deployer, governance, keeper, guardian, token):
    
    strategist = deployer
    want = token

    vault = Vault.deploy({"from": deployer})
    vault.initialize(
      token, governance, keeper, guardian, False, "", ""
    )
    vault.setStrategist(deployer, {"from": governance})
    # NOTE: Vault starts unpaused

    performanceFeeGovernance = 1000
    performanceFeeStrategist = 1000
    withdrawalFee = 50

    strategy = DemoStrategy.deploy({"from": deployer})
    strategy.initialize(
      governance, strategist, vault, keeper, guardian, [token], [performanceFeeGovernance, performanceFeeStrategist, withdrawalFee]
    )
    # NOTE: Strategy starts unpaused

    # Addresses
    assert strategy.want() == want
    assert strategy.governance() == governance
    assert strategy.strategist() == strategist
    assert strategy.keeper() == keeper
    assert strategy.vault() == vault
    assert strategy.guardian() == guardian

    # Params

    assert strategy.withdrawalMaxDeviationThreshold() == 50
    assert strategy.performanceFeeGovernance() == performanceFeeGovernance
    assert strategy.performanceFeeStrategist() == performanceFeeStrategist
    assert strategy.withdrawalFee() == withdrawalFee
    assert strategy.MAX_FEE() == 10_000
