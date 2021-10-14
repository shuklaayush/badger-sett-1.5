import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

## Test for deposit with no initial shares
def test_deposit_no_initial_shares(deployer, vault, strategy, want):
    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.8)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    vault.deposit(depositAmount, {"from": deployer})

    shares = vault.balanceOf(deployer)

    assert shares == depositAmount

## Test for deposit with some initial shares
def test_deposit_some_initial_shares(deployer, vault, strategy, want):
    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    vault.deposit(depositAmount, {"from": deployer})

    shares = vault.balanceOf(deployer)

    assert shares == depositAmount
    assert vault.balance() == depositAmount

    ## deployer deposit's again

    # inital shares of deployer
    initial_shares = vault.balanceOf(deployer)

    depositAmount = int(want.balanceOf(deployer) * 0.25)

    vault.deposit(depositAmount, {"from": deployer})

    final_shares = vault.balanceOf(deployer)

    assert final_shares - initial_shares == depositAmount

## Test for deposit with some initial + an harvest
def test_deposit_shares_harvest(deployer, vault, strategy, want):
    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})
    shares = vault.balanceOf(deployer)

    assert shares == depositAmount
    assert vault.balance() == depositAmount

    ## deployer deposit's again

    # inital shares of deployer
    initial_shares = vault.balanceOf(deployer)
    depositAmount = int(want.balanceOf(deployer) * 0.25)

    assert depositAmount > 0

    vault.deposit(depositAmount, {"from": deployer})
    final_shares = vault.balanceOf(deployer)
    assert final_shares - initial_shares == depositAmount

    ## Transfer some want to strategy which will represent harvest
    before_mint = vault.balance()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = vault.balance()
    assert after_mint - before_mint == mint_amount

    ## Deposit when initial_shares + harvest
    balance_before_deposit = vault.balance()
    depositAmount = int(want.balanceOf(deployer) * 0.1)

    assert depositAmount > 0

    vault.deposit(depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount


## Test for withdrawal all
def test_withdrawalAll(deployer, vault, strategy, want):

    # Setup #

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    # ----- #

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)

    vault.withdrawAll({"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)

    # As we are withdrawing all - Withdrawn amount should be equal to deposit amount of user
    assert user_balance_after_withdraw - user_balance_before_withdraw == depositAmount

    # vault balance should decrease propotionally
    assert vault_balance_before_withdraw - vault_balance_after_withdraw == depositAmount


## Test for withdrawing more shares than deposited
def test_withdrawalSome_more_than_deposited(deployer, vault, strategy, want):

    # Setup #

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    # ----- #

    withdraw_amount = depositAmount * 2

    with brownie.reverts():
        vault.withdraw(withdraw_amount, {"from": deployer})

## Test for withdrawal of a given amount of shares
def test_withdrawalSome(deployer, vault, strategy, want):

    # Setup #

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    # ----- #

    withdraw_amount = depositAmount // 10

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)

    vault.withdraw(withdraw_amount, {"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)

    # Withdrawn amount should be equal to withdraw_amount amount for user
    assert user_balance_after_withdraw - user_balance_before_withdraw == withdraw_amount

    # vault balance should decrease
    assert vault_balance_before_withdraw - vault_balance_after_withdraw == withdraw_amount

## Test for withdrawal after harvest
# NOTE: For now only withdrawalFee is taken into account 
# TODO: take into account performanceFeeGovernance and performanceFeeStrategist
def test_withdrawalAll_after_harvest(deployer, vault, strategy, want, withdrawalFee):

    # Setup #

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    ## Transfer some want to strategy which will represent harvest
    before_mint = vault.balance()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = vault.balance()
    assert after_mint - before_mint == mint_amount

    # ----- #

    withdraw_amount = depositAmount # As we are withdrawing all

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)

    vault.withdrawAll({"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)

    MAX_BPS = 10_000
    min_expected_withdrawn_amount = ((withdraw_amount + mint_amount) * strategy.withdrawalMaxDeviationThreshold()) / MAX_BPS
    min_expected_withdrawn_amount_after_withdrawalFee = min_expected_withdrawn_amount - ((min_expected_withdrawn_amount * withdrawalFee) / MAX_BPS)

    # Withdrawn amount should be >= withdraw_amount for user + min_expected_harvest_amount
    assert user_balance_after_withdraw - user_balance_before_withdraw >= min_expected_withdrawn_amount_after_withdrawalFee

    # vault balance decrease should be equal to withdraw_amount + 
    assert vault_balance_before_withdraw - vault_balance_after_withdraw == withdraw_amount + mint_amount

## Test for multiple withdrawals
def test_multiple_withdrawals(deployer, vault, strategy, want):

    # Setup #

    depositAmount = int(want.balanceOf(deployer) * 0.5)
    assert depositAmount > 0
    want.approve(vault.address, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    # ----- #

    for i in range(2):
        withdraw_amount = depositAmount // 10

        vault_balance_before_withdraw = vault.balance()
        user_balance_before_withdraw = want.balanceOf(deployer)

        vault.withdraw(withdraw_amount, {"from": deployer})

        vault_balance_after_withdraw = vault.balance()
        user_balance_after_withdraw = want.balanceOf(deployer)

        # Withdrawn amount should be equal to withdraw_amount amount for user
        assert user_balance_after_withdraw - user_balance_before_withdraw == withdraw_amount

        # vault balance should decrease
        assert vault_balance_before_withdraw - vault_balance_after_withdraw == withdraw_amount