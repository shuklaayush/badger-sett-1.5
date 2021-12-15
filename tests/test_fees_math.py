import brownie
from brownie import *

from helpers.constants import AddressZero
from helpers.utils import approx
from helpers.shares_math import get_performance_fees_shares, get_report_fees
from dotmap import DotMap

import pytest

MAX_BPS = 10_000


@pytest.fixture
def mint_amount():
    return 1e18

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


def setup_mint(strategy, want, mint_amount):
    ## Transfer some want to strategy which will represent harvest
    before_mint = strategy.balanceOf()
    want.mint(strategy, mint_amount)
    after_mint = strategy.balanceOf()
    assert after_mint - before_mint == mint_amount

    return mint_amount


def test_performance_fees_are_issued_as_shares(
    setup_share_math,
    strategy,
    want,
    governance,
    vault,
    mint_amount
):
    ## Get settings
    treasury = vault.treasury()
    strategist = vault.strategist()
    perf_fees_gov = vault.performanceFeeGovernance()
    perf_fees_strategist = vault.performanceFeeStrategist()
    total_supply_before_deposit = vault.totalSupply()
    balance_before_deposit = vault.balance()
    time_of_prev_harvest = vault.lastHarvestedAt()

    vault.setManagementFee(
        0, {"from": governance}
    )  ## Set management fees to keep math simple

    ## Initial Values
    management_fee = vault.managementFee()
    strat_balance_before = want.balanceOf(strategy)
    strategist_shares_before = vault.balanceOf(strategist)
    governance_shares_before = vault.balanceOf(treasury)

    ## Mint 1 ETH of want
    setup_mint(strategy, want, mint_amount)

    ## Delta math
    strat_balance_after = want.balanceOf(strategy)
    strat_harvest_gain = strat_balance_after - strat_balance_before

    ## NOTE: This test is kind of sketch as the function is doing some roundings
    expected_strategist_shares = get_performance_fees_shares(
        strat_harvest_gain,
        perf_fees_strategist,
        total_supply_before_deposit,
        balance_before_deposit,
    )

    ## Run the actual operation
    strategy.test_harvest(
        mint_amount,
        {"from": governance}
    )  # test_harvest to report harvest value to vault which will take respective fees

    time_of_this_harvest = vault.lastHarvestedAt()

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

    duration_of_harvest = time_of_this_harvest - time_of_prev_harvest

    report_fees = get_report_fees(strat_harvest_gain, perf_fees_gov, perf_fees_strategist, management_fee, duration_of_harvest, total_supply_before_deposit, balance_before_deposit)

    assert approx(
        report_fees.shares_perf_strategist,
        delta_strategist_shares,
        1,
    )
    assert approx(
        report_fees.shares_management + report_fees.shares_perf_treasury,
        delta_governance_shares,
        1,
    )


def test_performance_fees_are_issued_to_treasury_and_strategist(
    setup_share_math,
    strategy,
    want,
    governance,
    vault,
    mint_amount
):
    """
        This is the more proper test for shares issuance
    """

    ## Get settings
    treasury = vault.treasury()
    strategist = vault.strategist()
    perf_fees_gov = vault.performanceFeeGovernance()
    perf_fees_strategist = vault.performanceFeeStrategist()
    total_supply_before_deposit = vault.totalSupply()
    balance_before_deposit = vault.balance()
    time_of_prev_harvest = vault.lastHarvestedAt()

    ## Initial Values
    management_fee = vault.managementFee()
    strat_balance_before = want.balanceOf(strategy)
    strategist_shares_before = vault.balanceOf(strategist)
    governance_shares_before = vault.balanceOf(treasury)

    ## Mint 1 ETH of want
    setup_mint(strategy, want, mint_amount)

    ## Delta math
    strat_balance_after = want.balanceOf(strategy)
    strat_harvest_gain = strat_balance_after - strat_balance_before

    ## NOTE: This test is kind of sketch as the function is doing some roundings
    expected_strategist_shares = get_performance_fees_shares(
        strat_harvest_gain,
        perf_fees_strategist,
        total_supply_before_deposit,
        balance_before_deposit,
    )

    ## Run the actual operation
    strategy.test_harvest(
        mint_amount,
        {"from": governance}
    )  # test_harvest to report harvest value to vault which will take respective fees

    time_of_this_harvest = vault.lastHarvestedAt()

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

    duration_of_harvest = time_of_this_harvest - time_of_prev_harvest

    report_fees = get_report_fees(strat_harvest_gain, perf_fees_gov, perf_fees_strategist, management_fee, duration_of_harvest, total_supply_before_deposit, balance_before_deposit)

    assert approx(
        report_fees.shares_perf_strategist,
        delta_strategist_shares,
        1,
    )
    assert approx(
        report_fees.shares_management + report_fees.shares_perf_treasury,
        delta_governance_shares,
        1,
    )


def test_zero_fee(
    setup_share_math,
    strategy,
    want,
    governance,
    vault,
    mint_amount
):
    """
        This is the more proper test for shares issuance
    """

    ## Get settings
    treasury = vault.treasury()
    strategist = vault.strategist()

    ## Initial Values
    strategist_shares_before = vault.balanceOf(strategist)
    governance_shares_before = vault.balanceOf(treasury)

    ## Mint 1 ETH of want
    setup_mint(strategy, want, mint_amount)

    vault.setPerformanceFeeGovernance(0, {"from": governance})
    vault.setManagementFee(0, {"from": governance})

    # If strategist address is 0, then there won't be any strategiest performance fee
    vault.setStrategist(AddressZero, {"from": governance})

    ## Run the actual operation
    strategy.test_harvest(
        mint_amount,
        {"from": governance}
    )  # test_harvest to report harvest value to vault which will take respective fees

    strategist_shares_after = vault.balanceOf(strategist)
    governance_shares_after = vault.balanceOf(treasury)

    assert strategist_shares_after == strategist_shares_before
    assert governance_shares_after == governance_shares_before