import brownie
from brownie import (
    Vault
)

from helpers.constants import AddressZero

## Test Permissioned actions
def test_setRewards(deployed_vault, governance, rando):
  
  # setting rewards address
  deployed_vault.setRewards(deployed_vault, {"from": governance})

  assert deployed_vault.rewards() == deployed_vault.address

  # setRewards from random user should fail
  with brownie.reverts():
    deployed_vault.setRewards(deployed_vault, {"from": rando})

def test_setGuestList(deployed_gueslist, governance, rando):
  
  vault = deployed_gueslist.vault
  guestlist = deployed_gueslist.guestlist
  
  # setting guestlist address
  vault.setGuestList(guestlist, {"from": governance})

  assert vault.guestList() == guestlist.address

  # setGuestList from random user should fail
  with brownie.reverts():
    vault.setGuestList(guestlist, {"from": rando})

def test_setGuardian(deployed_vault, deployer, governance, rando):
  
  # setting address(0) should revert
  with brownie.reverts("Address cannot be 0x0"):
    deployed_vault.setGuardian(AddressZero, {"from": governance})
  
  # setting guardian address
  deployed_vault.setGuardian(rando, {"from": governance})

  assert deployed_vault.guardian() == rando

  # setGuardian from random user should fail
  with brownie.reverts():
    deployed_vault.setRewards(rando, {"from": deployer})

def test_setMin(deployed_vault, governance, rando):
  
  # setting min > max should revert
  with brownie.reverts("min should be <= max"):
    deployed_vault.setMin(deployed_vault.max() + 1000, {"from": governance})
  
  # setting min
  deployed_vault.setMin(1_000, {"from": governance})

  assert deployed_vault.min() == 1_000

  # setting min from random user should fail
  with brownie.reverts():
    deployed_vault.setMin(1_000, {"from": rando})

def test_setManagementFees(deployed_vault, governance, rando):
  
  # setting min > max should revert
  with brownie.reverts("excessive-management-fee"):
    deployed_vault.setManagementFees(deployed_vault.max() + 1000, {"from": governance})
  
  # setting managementFee
  deployed_vault.setManagementFees(1_000, {"from": governance})

  assert deployed_vault.managementFee() == 1_000

  # setting managementFee from random user should fail
  with brownie.reverts("onlyGovernance"):
    deployed_vault.setManagementFees(5_000, {"from": rando})

def test_config_pause_unpause(deployed_vault, governance, rando):

    # Pause Vault
    deployed_vault.pause({"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setRewards(rando, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setStrategy(rando, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setGuestList(rando, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setMin(100, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setGuardian(rando, {"from": governance})

    # unpause Vault, now we should be able to set everything
    deployed_vault.unpause({"from": governance})

    deployed_vault.setRewards(rando, {"from": governance})
    deployed_vault.setStrategy(rando, {"from": governance})
    deployed_vault.setGuestList(rando, {"from": governance})
    deployed_vault.setMin(100, {"from": governance})
    deployed_vault.setGuardian(rando, {"from": governance})
