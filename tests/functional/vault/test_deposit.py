import brownie
from brownie import *
from helpers.constants import MaxUint256

from dotmap import DotMap
import pytest

@pytest.fixture
def deposit_setup(deploy_complete, deployer, governance):
    
    want = deploy_complete.want
    vault = deploy_complete.vault

    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.01)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    return DotMap(
        deployed_vault = vault,
        want = want,
        depositAmount = depositAmount
    )

def test_deposit(deposit_setup, deployer, governance):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want
    depositAmount = deposit_setup.depositAmount

    # Test basic deposit
    balance_before_deposit = vault.balance()

    vault.deposit(depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount 

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.deposit(depositAmount, {"from": deployer})

def test_depositFor(deposit_setup, deployer, governance, rando):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want
    depositAmount = deposit_setup.depositAmount

    # Test depositFor rando user
    balance_before_deposit = vault.balance()

    vault.depositFor(rando, depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount
    # check if balance is deposited for rando 
    assert vault.balanceOf(rando) == depositAmount

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.depositFor(rando, depositAmount, {"from": deployer})

def test_depositAll(deposit_setup, deployer, governance):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want
    
    depositAmount = want.balanceOf(deployer)

    # Test depositAll
    balance_before_deposit = vault.balance()

    vault.depositAll({"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount 

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.depositAll({"from": deployer})