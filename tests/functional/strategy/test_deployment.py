import brownie
from brownie import Vault, MockStrategy

from helpers.constants import AddressZero

performanceFeeGovernance = 1000
performanceFeeStrategist = 1000
withdrawalFee = 50
managementFee = 50

# Test's strategy's deployment
def test_strategy_deployment(
    deployer, governance, keeper, guardian, strategist, token, badgerTree, badger
):

    want = token

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

    strategy = MockStrategy.deploy({"from": deployer})

    with brownie.reverts("Address 0"):
        strategy.initialize(AddressZero, [token, badger])

    strategy.initialize(vault, [token, badger])
    # NOTE: Strategy starts unpaused

    # Addresses
    assert strategy.want() == want
    assert strategy.governance() == governance
    assert strategy.keeper() == keeper
    assert strategy.vault() == vault
    assert strategy.guardian() == guardian

    # Params

    assert strategy.withdrawalMaxDeviationThreshold() == 50
    assert strategy.MAX_BPS() == 10_000
