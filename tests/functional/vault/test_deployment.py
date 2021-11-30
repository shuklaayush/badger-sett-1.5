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
    assert vault.min() == 10_000
    assert vault.performanceFeeGovernance() == performanceFeeGovernance
    assert vault.performanceFeeStrategist() == performanceFeeStrategist
    assert vault.withdrawalFee() == withdrawalFee
    assert vault.managementFee() == managementFee
    assert vault.MAX_BPS() == 10_000
    assert vault.maxPerformanceFee() == 3_000
    assert vault.maxWithdrawalFee() == 100


def test_vault_deployment_badTokenAddress(
    deployer, governance, keeper, guardian, strategist, badgerTree
):
    vault = Vault.deploy({"from": deployer})
    with brownie.reverts("dev: _token address should not be zero"):
        vault.initialize(
            AddressZero,
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
