"""
What happens if we gift a random token to the strat?
"""
import brownie
from brownie import accounts, interface, MockToken

def test_report_an_extra_token(strategy, badgerTree, strategist, treasury, vault):
  """
  Proves that the strat using `_processExtraToken` will handle perf fee as well as send to tree
  """
  ## Badger Treasury
  donator = accounts.at("0x4441776e6a5d61fa024a5117bfc26b953ad1f425", force=True)

  ## Badger
  extra_token = interface.IERC20("0x3472A5A71965499acd81997a54BBA8D852C6E53d") 

  ## Initial balances
  initial_tree_balance = extra_token.balanceOf(badgerTree)
  initial_treasury_balance = extra_token.balanceOf(treasury)
  initial_strategist_balance = extra_token.balanceOf(strategist)

  ## Send the gift and report it
  amount = 1e18
  extra_token.transfer(strategy, amount, {"from": donator})
  strategy.test_harvest_only_emit(extra_token, amount, {"from": strategist})

  ## There was a net positive balance increase
  assert extra_token.balanceOf(badgerTree) > initial_tree_balance
  assert extra_token.balanceOf(treasury) > initial_treasury_balance
  assert extra_token.balanceOf(strategist) > initial_strategist_balance

  ## More rigorously
  perf_fee_gov = vault.performanceFeeGovernance()
  perf_fee_strat = vault.performanceFeeStrategist()
  max = vault.MAX_BPS()

  fee_gov = amount * perf_fee_gov / max
  fee_strat = amount * perf_fee_strat / max

  to_tree = amount - fee_gov - fee_strat

  assert extra_token.balanceOf(badgerTree) == initial_tree_balance + to_tree
  assert extra_token.balanceOf(treasury) == initial_treasury_balance + fee_gov
  assert extra_token.balanceOf(strategist) == initial_strategist_balance + fee_strat


def test_withdraw_another_token_from_strat(strategy, strategist, governance, vault, deployer):
    mint_amount = 10e18
    extra_token = MockToken.deploy({"from": deployer})
    extra_token.initialize(
        [strategy], [mint_amount]
    )

    prev_gov_bal = extra_token.balanceOf(governance)

    vault.sweepExtraToken(extra_token, {"from": strategist})

    after_gov_bal = extra_token.balanceOf(governance)

    assert after_gov_bal - prev_gov_bal == mint_amount



def test_withdraw_another_token_from_vault(strategist, governance, vault, deployer):
    mint_amount = 10e18
    extra_token = MockToken.deploy({"from": deployer})
    extra_token.initialize(
        [vault], [mint_amount]
    )

    prev_gov_bal = extra_token.balanceOf(governance)

    vault.sweepExtraToken(extra_token, {"from": strategist})

    after_gov_bal = extra_token.balanceOf(governance)

    assert after_gov_bal - prev_gov_bal == mint_amount
