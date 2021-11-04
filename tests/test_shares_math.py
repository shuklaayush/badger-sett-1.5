import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.utils import (
    approx,
)
from dotmap import DotMap

import pytest

MAX_BPS = 10_000

## Tests for withdrawal's
# NOTE: For now only withdrawalFee is taken into account
# TODO: take into account performanceFeeGovernance and performanceFeeStrategist
# TODO: Refactor the ones with min_ they will cause issues (democratized loss)
# TODO: Test for vault loosing ppfs below 1, how does the vault code react?
# TODO: Add a test that prooves that even when taking withdrawal fees, the sharePrice is stable (no negative inflation)

## Test for deposit with no initial shares
def test_deposit_no_initial_shares(deployer, vault, want):
    """
        If I deposit X and the vault has 0, then I will get X shares
    """
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
def test_deposit_some_initial_shares(deployer, vault, want):
    """
        If I deposit X + Y and there's X + Y value (no harvest)
        I'll have X + Y shares (1-1)
    """
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


## Test for deposit + earn with some initial + an harvest
def test_deposit_earn_harvest(deployer, governance, vault, strategy, want):
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
    initial_shares = vault.balanceOf(deployer)

    assert initial_shares == depositAmount
    assert vault.balance() == depositAmount

    vault.earn({"from": governance})

    ## Transfer some want to strategy which will represent harvest
    before_mint = vault.balance()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = vault.balance()
    assert after_mint - before_mint == mint_amount

    ## Deposit when initial_shares + harvest
    balance_before_deposit = vault.balance()
    total_supply_before_deposit = vault.totalSupply()
    depositAmount = int(want.balanceOf(deployer) * 0.1)

    assert depositAmount > 0

    vault.deposit(depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()
    

    ## Sanity check, deposit has happened
    assert balance_after_deposit - balance_before_deposit == depositAmount

    new_shares = vault.balanceOf(deployer)
    delta_shares = new_shares - initial_shares

    ## Math from code
    expected_shares = depositAmount * total_supply_before_deposit / balance_before_deposit

    assert approx(
        delta_shares,
        expected_shares,
        100 ## Rounding down to 100 wei
    )


## Test for withdrawal all
def test_withdrawalAll(
    setup_share_math, deployer, governance, vault, strategy, want, withdrawalFee
):

    depositAmount = setup_share_math.depositAmount

    withdraw_amount = depositAmount

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)

    vault.withdrawAll({"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)

    vault_ppfs_before_withdraw = 1e18 ## No harvest means it's 1
    value = withdraw_amount * vault_ppfs_before_withdraw / 1e18
    expected_withdrawn = value - (value * withdrawalFee / MAX_BPS)
    delta_user = user_balance_after_withdraw - user_balance_before_withdraw
    # As we are withdrawing all - Withdrawn amount should be equal to deposit amount of user
    assert (
        delta_user == expected_withdrawn
    )

    delta_vault = vault_balance_before_withdraw - vault_balance_after_withdraw
    withdrawal_fee = withdraw_amount * vault.withdrawalFee() / vault.MAX()
    # vault balance should decrease propotionally
    assert  delta_vault == withdraw_amount - withdrawal_fee
    ## i.e vault has retained the withdrawal fees


## Test for withdrawing more shares than deposited
def test_withdrawalSome_more_than_deposited(
    setup_share_math, deployer, governance, vault, strategy, want
):

    depositAmount = setup_share_math.depositAmount

    withdraw_amount = depositAmount * 2

    with brownie.reverts():
        vault.withdraw(withdraw_amount, {"from": deployer})
    
    vault.withdraw(depositAmount)


## Test for withdrawal of a given amount of shares
def test_withdrawSome(
    setup_share_math, deployer, governance, vault, strategy, want, withdrawalFee
):

    depositAmount = setup_share_math.depositAmount

    withdraw_amount = depositAmount // 10

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)
    vault_ppfs_before_withdraw = vault.getPricePerFullShare()

    vault.withdraw(withdraw_amount, {"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)

    value = withdraw_amount * vault_ppfs_before_withdraw / 1e18
    expected_withdrawn = value - (value * withdrawalFee / MAX_BPS)
    delta_user = user_balance_after_withdraw - user_balance_before_withdraw
    assert delta_user == expected_withdrawn


    delta_vault = vault_balance_before_withdraw - vault_balance_after_withdraw
    withdrawal_fee = withdraw_amount * vault.withdrawalFee() / vault.MAX()
    # vault balance should decrease propotionally
    assert  delta_vault == withdraw_amount - withdrawal_fee
    ## i.e vault has retained the withdrawal fees


## Test for withdrawal after harvest
def test_withdrawalAll_after_harvest(
    setup_share_math, deployer, governance, vault, strategy, want, withdrawalFee
):

    # Setup #
    depositAmount = setup_share_math.depositAmount

    ## Transfer some want to strategy which will represent harvest
    before_mint = vault.balance()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = vault.balance()
    assert after_mint - before_mint == mint_amount

    # ----- #

    withdraw_amount = depositAmount  # As we are withdrawing all

    vault_balance_before_withdraw = vault.balance()
    user_balance_before_withdraw = want.balanceOf(deployer)
    vault_ppfs_before_withdraw = vault.getPricePerFullShare()

    vault.withdrawAll({"from": deployer})

    vault_balance_after_withdraw = vault.balance()
    user_balance_after_withdraw = want.balanceOf(deployer)
    user_delta_balance = user_balance_after_withdraw - user_balance_before_withdraw
    ## Shares burnt = withdraw_amount


    ## Math on what they should get
    ## They should get: new_value_of_shares - withdrawal_fee

    ## The minimum they get is the value of initial shares - withdrawal_fee
    initial_ppfs = 1
    ## The min without accounting for harvest
    min_value_withdrawn = withdraw_amount * initial_ppfs - (withdraw_amount * withdrawalFee / MAX_BPS)

    assert user_delta_balance > min_value_withdrawn ## Proof of no loss

    ## Now proof of correct math
    ## The user withdraws all shares they have, they should get the new 
    # value = ppfs * shares
    # withdrawn = value - withdrawalFee(value)

    value = withdraw_amount * vault_ppfs_before_withdraw / 1e18
    expected_withdrawn = value - (value * withdrawalFee / MAX_BPS)


    # Delta is greater than or equal to expected
    assert user_delta_balance == expected_withdrawn

    # Reflexive property, the funds we sent to the user are the same as the vault delta
    assert vault_balance_before_withdraw - vault_balance_after_withdraw == expected_withdrawn


## Test for multiple withdrawals
def test_multiple_withdrawals(
    setup_share_math, deployer, governance, vault, strategy, want, withdrawalFee
):

    depositAmount = setup_share_math.depositAmount

    for i in range(1):
        withdraw_amount = depositAmount // 10

        vault_balance_before_withdraw = vault.balance()
        user_shares_before = vault.balanceOf(deployer)
        user_balance_before_withdraw = want.balanceOf(deployer)
        vault_ppfs_before_withdraw = vault.getPricePerFullShare()

        vault.withdraw(withdraw_amount, {"from": deployer})

        vault_balance_after_withdraw = vault.balance()
        user_shares_after = vault.balanceOf(deployer)

        user_balance_after_withdraw = want.balanceOf(deployer)
        user_delta_balance = user_balance_after_withdraw - user_balance_before_withdraw

        ## Shares burnt = withdraw_amount
        assert user_shares_before - user_shares_after == withdraw_amount ## We burnt the right amount of shares


        ## Math on what they should get
        ## They should get: new_value_of_shares - withdrawal_fee

        ## The minimum they get is the value of initial shares - withdrawal_fee
        initial_ppfs = 1
        ## The min without accounting for harvest
        min_value_withdrawn = withdraw_amount * initial_ppfs - (withdraw_amount * withdrawalFee / MAX_BPS)

        assert user_delta_balance == min_value_withdrawn ## Proof of no loss as we didn't harvest

        ## Now proof of correct math
        ## The user withdraws all shares they have, they should get the new 
        # value = ppfs * shares
        # withdrawn = value - withdrawalFee(value)

        value = withdraw_amount * vault_ppfs_before_withdraw / 1e18
        expected_withdrawn = value - (value * withdrawalFee / MAX_BPS)


        # Delta is greater than or equal to expected
        assert user_delta_balance == expected_withdrawn

        # Reflexive property, the funds we sent to the user are the same as the vault delta
        assert vault_balance_before_withdraw - vault_balance_after_withdraw == expected_withdrawn