import brownie
from brownie import *
from helpers.constants import MaxUint256

from dotmap import DotMap
import pytest


def test_earn(deploy_complete, deployer, governance, randomUser, keeper):

    want = deploy_complete.want
    vault = deploy_complete.vault
    strategy = deploy_complete.strategy

    # Deposit
    assert want.balanceOf(deployer) > 0
    assert want.balanceOf(randomUser) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer / randomUser
    assert vault.balanceOf(deployer) == 0
    assert vault.balanceOf(randomUser) == 0

    depositAmount_deployer = int(want.balanceOf(deployer) * 0.01)
    assert depositAmount_deployer > 0

    depositAmount_randomUser = int(want.balanceOf(randomUser) * 0.01)
    assert depositAmount_randomUser > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})
    want.approve(vault.address, MaxUint256, {"from": randomUser})

    # Deposit for deployer and earn

    vault.deposit(depositAmount_deployer, {"from": deployer})

    # Trying to call earn from unauthorized actors should fail
    with brownie.reverts("onlyAuthorizedActors"):
        vault.earn({"from": randomUser})

    available_before_earn = (
        vault.available()
    )  # this amount should be deposited into the strategy
    vault.earn({"from": governance})

    assert strategy.balanceOf() == available_before_earn

    # Now randomUser user deposits and earn

    vault.deposit(depositAmount_randomUser, {"from": randomUser})

    before_earn_balance_strat = strategy.balanceOf()
    available_before_earn = (
        vault.available()
    )  # this amount should be deposited into the strategy
    vault.earn({"from": governance})

    after_earn_balance_strat = strategy.balanceOf()

    assert after_earn_balance_strat - before_earn_balance_strat == available_before_earn

    # When vault is paused earn still works

    vault.deposit(depositAmount_deployer, {"from": deployer})

    vault.pause({"from": governance})

    assert vault.paused() == True

    vault.earn({"from": governance})
    
    # When strategy is paused earn is paused
    strategy.pause({"from": governance})

    assert strategy.paused() == True
    with brownie.reverts("Pausable: paused"):
        vault.earn({"from": governance})

    vault.unpause({"from": governance})

    assert vault.paused() == False

    # When deposits are paused earn should fail

    vault.pauseDeposits({"from": governance})

    assert vault.pausedDeposit() == True

    with brownie.reverts("pausedDeposit"):
        vault.earn({"from": governance})