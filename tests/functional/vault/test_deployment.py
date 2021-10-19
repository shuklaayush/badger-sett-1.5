import brownie
from brownie import (
    Vault
)

from helpers.constants import AddressZero

# Test's vault deployment
def test_vault_deployment(deployer, governance, keeper, guardian, token):
    vault = Vault.deploy({"from": deployer})
    vault.initialize(
      token, governance, keeper, guardian, False, "", ""
    )
    vault.setStrategist(deployer, {"from": governance})
    
    # Addresses
    assert vault.governance() == governance
    assert vault.keeper() == keeper
    assert vault.guardian() == guardian
    assert vault.token() == token
    # NOTE: when rewards contract check rewards address is set properly

    # Params 
    assert vault.min() == 10_000

def test_vault_deployment_badTokenAddress(deployer, governance, keeper, guardian):
    vault = Vault.deploy({"from": deployer})
    with brownie.reverts("Token address should not be 0x0"):
      vault.initialize(
        AddressZero, governance, keeper, guardian, False, "", ""
      )
