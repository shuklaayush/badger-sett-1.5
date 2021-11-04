"""
  Set of functions to calculate shares burned, fees, and want withdrawn or deposited
"""

## TODO: Move this code in tests so it's used there as well

MAX_BPS = 10_000

def from_want_to_shares(want_deposited, total_supply_before_deposit, balance_before_deposit):
  """
    Used to estimate how many shares you'll get for a deposit
  """
  ## Math from Soldity
  expected_shares = want_deposited * total_supply_before_deposit / balance_before_deposit

  return expected_shares

def from_shares_to_want(shares_to_burn, ppfs_before_withdraw, vault_decimals, withdrawal_fee_bps):
  """
    Used to estimate how much want you'll get for a withdrawal, by burning the shares
  """
  ## Math from Solidity
  value = shares_to_burn * ppfs_before_withdraw / 10 ** vault_decimals
  expected_withdrawn = value - (value * withdrawal_fee_bps / MAX_BPS)

  return expected_withdrawn

def get_withdrawal_fees_in_want(shares_to_burn, ppfs_before_withdraw, vault_decimals, withdrawal_fee_bps):
  """
    Used to calculate the fees (in want) the treasury will receive when taking withdrawal fees
  """
  ## Math from Solidity
  value = shares_to_burn * ppfs_before_withdraw / 10 ** vault_decimals
  fees = (value * withdrawal_fee_bps / MAX_BPS)

  return fees

def get_withdrawal_fees_in_shares(shares_to_burn, ppfs_before_withdraw, vault_decimals, withdrawal_fee_bps, total_supply_before_withdraw, vault_balance_before_withdraw):
  """
    Used to calculate the shares that will be issued for treasury when taking withdrawal fee during a withdrwal
  """
  ## More rigorously: We had an increase in shares equal to depositing the fees
  expected_fee_in_want = get_withdrawal_fees_in_want(shares_to_burn, ppfs_before_withdraw, vault_decimals, withdrawal_fee_bps)

  ## Math from code ## Issues shares based on want * supply / balance
  expected_shares = expected_fee_in_want * total_supply_before_withdraw / vault_balance_before_withdraw
  return expected_shares