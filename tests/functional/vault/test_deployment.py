import brownie
from brownie import Vault

from helpers.constants import AddressZero

performanceFeeGovernance = 1000
performanceFeeStrategist = 1000
withdrawalFee = 50
managementFee = 50

# Test's vault deployment
def test_vault_deployment(deployer, governance, keeper, guardian, strategist, badgerTree, token):
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
    assert vault.toEarnBps() == 10_000
    assert vault.performanceFeeGovernance() == performanceFeeGovernance
    assert vault.performanceFeeStrategist() == performanceFeeStrategist
    assert vault.withdrawalFee() == withdrawalFee
    assert vault.managementFee() == managementFee
    assert vault.MAX_BPS() == 10_000
    assert vault.maxPerformanceFee() == 3_000
    assert vault.maxWithdrawalFee() == 100


def test_vault_deployment_badArgument(
    deployer, governance, keeper, guardian, strategist, badgerTree, token
):
    vault = Vault.deploy({"from": deployer})
    default_address_args = [token, governance, keeper, guardian, governance, strategist, badgerTree]

    for i in range(len(default_address_args)):
        address_args = [default_address_args[j] if j != i else AddressZero for j in range(len(default_address_args))]
        
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