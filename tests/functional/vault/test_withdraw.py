import brownie
from brownie import *
from helpers.constants import MaxUint256

from dotmap import DotMap
import pytest


@pytest.fixture
def withdraw_setup(deploy_complete, deployer, governance, randomUser, keeper):

    want = deploy_complete.want
    vault = deploy_complete.vault
    strategy = deploy_complete.strategy

    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.1)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})
    vault.earn({"from": governance})

    return DotMap(
        deployed_vault=vault, want=want, depositAmount=depositAmount, strategy=strategy
    )


def test_withdrawToVault(withdraw_setup, deployer, governance, randomUser):

    want = withdraw_setup.want
    vault = withdraw_setup.deployed_vault
    strategy = withdraw_setup.strategy

    balance_in_strategy = strategy.balanceOf()
    balance_vault_before_withdrawToVault = want.balanceOf(vault)

    # withdrawToVault should withdrawAll from the strategy and move it into vault

    # should fail if msg.sender != strategist/governance

    with brownie.reverts("onlyGovernanceOrStrategist"):
        vault.withdrawToVault({"from": randomUser})

    # withdrawToVault should work if strategy is paused
    strategy.pause({"from": governance})
    vault.withdrawToVault({"from": governance})
    strategy.unpause({"from": governance})

    vault.withdrawToVault({"from": governance})

    balance_vault_after_withdrawToVault = want.balanceOf(vault)

    assert (
        balance_vault_after_withdrawToVault - balance_vault_before_withdrawToVault
        == balance_in_strategy
    )


def test_withdraw(withdraw_setup, deployer, governance, randomUser):

    want = withdraw_setup.want
    vault = withdraw_setup.deployed_vault
    strategy = withdraw_setup.strategy
    depositAmount = withdraw_setup.depositAmount

    balance_in_strategy = strategy.balanceOf()
    balance_vault_before_withdraw = vault.balance()

    withdraw_amount = depositAmount // 10

    # withdraw should fail if vault is paused
    vault.pause({"from": governance})
    with brownie.reverts("Pausable: paused"):
        vault.withdraw(withdraw_amount, {"from": deployer})
    vault.unpause({"from": governance})

    vault.withdraw(withdraw_amount, {"from": deployer})

    balance_vault_after_withdraw = vault.balance()

    assert (
        balance_vault_before_withdraw - balance_vault_after_withdraw
        == withdraw_amount - vault.withdrawalFee() * withdraw_amount / vault.MAX_BPS()
    )

    with brownie.reverts("0 Shares"):
        vault.withdraw(0, {"from": deployer})


def test_withdrawAll(withdraw_setup, deployer, governance, randomUser):

    want = withdraw_setup.want
    vault = withdraw_setup.deployed_vault
    strategy = withdraw_setup.strategy
    depositAmount = withdraw_setup.depositAmount

    balance_in_strategy = strategy.balanceOf()
    balance_vault_before_withdraw = want.balanceOf(vault)

    # withdrawAll should fail if vault is paused
    vault.pause({"from": governance})
    with brownie.reverts("Pausable: paused"):
        vault.withdrawAll({"from": deployer})
    vault.unpause({"from": governance})

    vault.withdrawAll({"from": deployer})

    balance_vault_after_withdraw = want.balanceOf(vault)

    assert (
        balance_vault_after_withdraw
        - depositAmount * vault.withdrawalFee() / vault.MAX_BPS()
        == 0
    )


def test_withdrawOther(withdraw_setup, deployer, governance, randomUser):

    want = withdraw_setup.want
    vault = withdraw_setup.deployed_vault
    strategy = withdraw_setup.strategy
    depositAmount = withdraw_setup.depositAmount

    balance_in_strategy = strategy.balanceOf()
    balance_vault_before_withdraw = want.balanceOf(vault)

    # Creating another token
    token2 = MockToken.deploy({"from": deployer})
    token2.initialize(
        [deployer.address, randomUser.address], [100 * 10 ** 18, 100 * 10 ** 18]
    )

    # sending token2 to strategy
    mintAmount = 100e18
    token2.mint(strategy, mintAmount)

    # should fail if msg.sender != strategist/governance

    with brownie.reverts("onlyGovernanceOrStrategist"):
        vault.sweepExtraToken(token2.address, {"from": randomUser})

    vault.withdrawAll({"from": deployer})

    balance_vault_after_withdraw = want.balanceOf(vault)

    assert (
        balance_vault_after_withdraw
        - depositAmount * vault.withdrawalFee() / vault.MAX_BPS()
        == 0
    )


def test_withdraw_lossy(withdraw_setup, deployer, governance):
    want = withdraw_setup.want

    vault = withdraw_setup.deployed_vault
    strategy = withdraw_setup.strategy
    depositAmount = withdraw_setup.depositAmount

    vault.setWithdrawalFee(0, {"from": governance})

    balance_deployer_before = want.balanceOf(deployer)

    withdraw_amount = depositAmount

    loss_bps = 10_000
    strategy.setLossBps(loss_bps, {"from": governance})

    with brownie.reverts("withdraw-exceed-max-deviation-threshold"):
        vault.withdraw(withdraw_amount, {"from": deployer})

    loss_bps = 10
    strategy.setLossBps(loss_bps, {"from": governance})

    vault.withdraw(withdraw_amount, {"from": deployer})

    balance_deployer_after = want.balanceOf(deployer)

    assert (
        balance_deployer_after - balance_deployer_before == withdraw_amount * (1 - loss_bps / 10_000)
    )