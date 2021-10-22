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

def test_setTreasury(deployed_vault, governance, rando):
  
  # setting treasury address
  deployed_vault.setTreasury(deployed_vault, {"from": governance})

  assert deployed_vault.treasury() == deployed_vault.address

  # setTreasury from random user should fail
  with brownie.reverts():
    deployed_vault.setTreasury(deployed_vault, {"from": rando})

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
  
  # setting min > MAX should revert
  with brownie.reverts("min should be <= MAX"):
    deployed_vault.setMin(deployed_vault.MAX() + 1_000, {"from": governance})
  
  # setting min
  deployed_vault.setMin(1_000, {"from": governance})

  assert deployed_vault.min() == 1_000

  # setting min from random user should fail
  with brownie.reverts():
    deployed_vault.setMin(1_000, {"from": rando})

def test_setMaxPerformanceFee(deployed_vault, governance, strategist, rando):
  
  # setting maxPeformanceFees > MAX should fail
  with brownie.reverts("excessive-performance-fee"):
    deployed_vault.setMaxPerformanceFee(deployed_vault.MAX() + 1_000, {"from": governance})
  
  # setting min
  deployed_vault.setMaxPerformanceFee(8_000, {"from": governance})

  assert deployed_vault.maxPerformanceFee() == 8_000

  # setting maxPeformanceFees from rando user / strategist should fail
  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxPerformanceFee(1_000, {"from": rando})

  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxPerformanceFee(1_000, {"from": strategist})

def test_setMaxWithdrawalFee(deployed_vault, governance, strategist, rando):
  
  # setting maxWithdrawalFee > MAX should fail
  with brownie.reverts("excessive-withdrawal-fee"):
    deployed_vault.setMaxWithdrawalFee(deployed_vault.MAX() + 1_000, {"from": governance})
  
  # setting setMaxWithdrawalFee
  deployed_vault.setMaxWithdrawalFee(1_000, {"from": governance})

  assert deployed_vault.maxWithdrawalFee() == 1_000

  # setting setMaxWithdrawalFee from rando user / strategist should fail
  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxWithdrawalFee(1_000, {"from": rando})

  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxWithdrawalFee(1_000, {"from": strategist})

def test_setMaxManagementFee(deployed_vault, governance, strategist, rando):
  
  # setting maxManagementFee > MAX should fail
  with brownie.reverts("excessive-management-fee"):
    deployed_vault.setMaxManagementFee(deployed_vault.MAX() + 1_000, {"from": governance})
  
  # setting setMaxWithdrawalFee
  deployed_vault.setMaxManagementFee(1_000, {"from": governance})

  assert deployed_vault.maxManagementFee() == 1_000

  # setting setMaxWithdrawalFee from rando user / strategist should fail
  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxManagementFee(1_000, {"from": rando})

  with brownie.reverts("onlyGovernance"):
    deployed_vault.setMaxManagementFee(1_000, {"from": strategist})

def test_setManagementFee(deployed_vault, governance, strategist, rando):
  
  # setting managementFee
  deployed_vault.setManagementFee(100, {"from": governance})

  assert deployed_vault.managementFee() == 100

  # setting managementFee from random user should fail
  with brownie.reverts("onlyGovernanceOrStrategist"):
    deployed_vault.setManagementFee(5_000, {"from": rando})
  
  # setting more that maxManagementFee should fail
  with brownie.reverts("excessive-management-fee"):
      deployed_vault.setManagementFee(2 * deployed_vault.maxManagementFee(), {"from": strategist})

def test_setWithdrawalFee(deployed_vault, governance, strategist, rando):

    withdrawalFee = 100

    # withdrawalFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        deployed_vault.setWithdrawalFee(withdrawalFee, {"from": rando})

    # setting withdrawalFee
    deployed_vault.setWithdrawalFee(withdrawalFee, {"from": governance})

    assert deployed_vault.withdrawalFee() == withdrawalFee

    # setting more that maxWithdrawalFee should fail
    with brownie.reverts("base-strategy/excessive-withdrawal-fee"):
        deployed_vault.setWithdrawalFee(2 * deployed_vault.maxWithdrawalFee(), {"from": strategist})

def test_setPerformanceFeeStrategist(deployed_vault, governance, strategist, rando):

    performanceFeeStrategist = 2_000 # increasing fees to compensate good strategist.

    # setPerformanceFeeStrategist from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        deployed_vault.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": rando})

    # setPerformanceFeeStrategist from governance
    deployed_vault.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": governance})

    # setPerformanceFeeStrategist from strategist
    deployed_vault.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": strategist})

    assert deployed_vault.performanceFeeStrategist() == performanceFeeStrategist

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("base-strategy/excessive-strategist-performance-fee"):
        deployed_vault.setPerformanceFeeStrategist(2 * deployed_vault.maxPerformanceFee(), {"from": strategist})

def test_setPerformanceFeeGovernance(deployed_vault, governance, strategist, rando):

    performanceFeeGovernance = 2_000

    # setPerformanceFeeGovernance from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        deployed_vault.setPerformanceFeeGovernance(performanceFeeGovernance, {"from": rando})

    # setPerformanceFeeGovernance from governance
    deployed_vault.setPerformanceFeeGovernance(performanceFeeGovernance, {"from": governance})

    # setPerformanceFeeGovernance from strategist
    deployed_vault.setPerformanceFeeGovernance(performanceFeeGovernance, {"from": strategist})

    assert deployed_vault.performanceFeeGovernance() == performanceFeeGovernance

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("base-strategy/excessive-governance-performance-fee"):
        deployed_vault.setPerformanceFeeGovernance(2 * deployed_vault.maxPerformanceFee(), {"from": strategist})

def test_config_pause_unpause(deployed_vault, governance, strategist, rando):

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

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setManagementFee(1_000, {"from": governance})
    
    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeGovernance(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeStrategist(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setWithdrawalFee(100, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setMaxPerformanceFee(8_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setMaxWithdrawalFee(8_000, {"from": governance})

    # unpause Vault, now we should be able to set everything
    deployed_vault.unpause({"from": governance})
  
    deployed_vault.setRewards(rando, {"from": governance})
    deployed_vault.setStrategy(rando, {"from": governance})
    deployed_vault.setGuestList(rando, {"from": governance})
    deployed_vault.setMin(100, {"from": governance})
    deployed_vault.setGuardian(rando, {"from": governance})
    deployed_vault.setMaxPerformanceFee(8_000, {"from": governance})
    deployed_vault.setMaxWithdrawalFee(8_000, {"from": governance})
    deployed_vault.setMaxManagementFee(8_000, {"from": governance})
    deployed_vault.setManagementFee(1_000, {"from": strategist})
    deployed_vault.setPerformanceFeeGovernance(2_000, {"from": strategist})
    deployed_vault.setPerformanceFeeStrategist(2_000, {"from": strategist})
    deployed_vault.setWithdrawalFee(100, {"from": strategist})
