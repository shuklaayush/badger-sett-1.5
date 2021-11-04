import brownie
from brownie import *

from helpers.utils import (
    approx,
)
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
