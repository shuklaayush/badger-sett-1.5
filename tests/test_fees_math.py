import brownie
from brownie import *

from helpers.utils import approx
from helpers.shares_math import get_performance_fees_shares
from dotmap import DotMap

import pytest

MAX_BPS = 10_000


def test_withdrawal_fees_are_issued_as_shares(
    setup_share_math, deployer, governance, vault, strategy, want, withdrawalFee
):
    fees_recipient = vault.treasury()
    treasury_shares_before = vault.balanceOf(fees_recipient)
    vault_balance_before_withdraw = vault.balance()
    total_supply_before_deposit = vault.totalSupply()

    vault_ppfs_before_withdraw = vault.getPricePerFullShare()
    shares_burnt = setup_share_math.depositAmount

    ## User withdraws
    vault.withdraw(shares_burnt, {"from": deployer})

    vault_balance_after_withdraw = vault.balance()

    treasury_shares_after = vault.balanceOf(fees_recipient)

    ## We had an increment in shares for treasury
    assert treasury_shares_after > treasury_shares_before

    ## More rigorously: We had an increase in shares equal to depositing the fees
    value = shares_burnt * vault_ppfs_before_withdraw / 1e18
    expected_fee_in_want = value * withdrawalFee / MAX_BPS

    ## Math from code ## Issues shares based on want * supply / balance
    expected_shares = (
        expected_fee_in_want
        * total_supply_before_deposit
        / vault_balance_before_withdraw
    )
    delta_shares = treasury_shares_after - treasury_shares_before
    assert expected_shares == delta_shares


def setup_mint(strategy, want):
    ## Transfer some want to strategy which will represent harvest
    before_mint = strategy.balanceOf()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = strategy.balanceOf()
    assert after_mint - before_mint == mint_amount


def test_performance_fees_are_issued_as_shares(
    setup_share_math,
    strategy,
    want,
    governance,
    vault,
):
    ## Get settings
    treasury = vault.treasury()
    strategist = vault.strategist()
    perf_fees_gov = vault.performanceFeeGovernance()
    perf_fees_strategist = vault.performanceFeeStrategist()
    total_supply_before_deposit = vault.totalSupply()
    balance_before_deposit = vault.balance()

    vault.setManagementFee(
        0, {"from": governance}
    )  ## Set management fees to keep math simple

    ## Initial Values
    strat_balance_before = want.balanceOf(strategy)
    strategist_shares_before = vault.balanceOf(strategist)
    governance_shares_before = vault.balanceOf(treasury)

    ## Mint 1 ETH of want
    setup_mint(strategy, want)

    ## Delta math
    strat_balance_after = want.balanceOf(strategy)
    strat_harvest_gain = strat_balance_after - strat_balance_before

    expected_strategist_shares = get_performance_fees_shares(
        strat_harvest_gain,
        perf_fees_strategist,
        total_supply_before_deposit,
        balance_before_deposit,
    )

    ## Run the actual operation
    strategy.test_harvest(
        {"from": governance}
    )  # test_harvest to report harvest value to vault which will take respective fees

    ## 1 Eth was harvested, we have to take perf fees
    strategist_shares_after = vault.balanceOf(strategist)
    governance_shares_after = vault.balanceOf(treasury)
    delta_strategist_shares = strategist_shares_after - strategist_shares_before
    delta_governance_shares = governance_shares_after - governance_shares_before

    assert approx(
        expected_strategist_shares,
        delta_strategist_shares,
        1,
    )
