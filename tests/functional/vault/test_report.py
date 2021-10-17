import brownie
from brownie import *
from helpers.constants import MaxUint256

from dotmap import DotMap
import pytest

MAX_BPS = 10_000

@pytest.fixture
def setup_report(deploy_complete, deployer, governance):
    
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

    # Deposit and earn
    vault.deposit(depositAmount, {"from": deployer})
    vault.earn({"from": governance})

    ## Transfer some want to strategy which will represent harvest
    before_mint = strategy.balanceOf()
    mint_amount = 1e18
    want.mint(strategy, mint_amount)
    after_mint = strategy.balanceOf()
    assert after_mint - before_mint == mint_amount

    # ----- #

    return DotMap(
        vault = vault,
        strategy = strategy,
        want = want,
        depositAmount = depositAmount
    )

def test_report_failed(setup_report, governance, rando, keeper):
    
    vault = setup_report.vault
    strategy = setup_report.strategy

    ## report should fail when vault is paused
    # Pausing vault
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        strategy.test_harvest({"from": keeper})

    vault.unpause({"from": governance})
    
    ## report should fail when strategy is paused
    # Pausing strategy
    strategy.pause({"from": governance})

    assert strategy.paused() == True

    with brownie.reverts("Pausable: paused"):
        strategy.test_harvest({"from": keeper})

    strategy.unpause({"from": governance})

    # report should fail report function is not called from strategy
    with brownie.reverts("onlyStrategy"):
        vault.report(1e18, 0, 0, 0, 0, {"from": rando})

    # harvest should fail when called by rando
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.test_harvest({"from": rando})


def test_report(setup_report, deployer, governance):
    
    vault = setup_report.vault
    strategy = setup_report.strategy

    balanceOfWantStrategy = strategy.balanceOfWant()
    
    feeGovernance = (1e18 * strategy.performanceFeeGovernance()) / MAX_BPS
    feeStrategist = (1e18 * strategy.performanceFeeStrategist()) / MAX_BPS

    total_supply_before_harvest = vault.totalSupply()
    pricePerFullShare_before_harvest = vault.getPricePerFullShare()

    # harvesting
    strategy.test_harvest({"from": governance})

    total_supply_after_harvest = vault.totalSupply()
    pricePerFullShare_after_harvest = vault.getPricePerFullShare()

    assert vault.lastHarvestAmount() == 1e18
    assert vault.assetsAtLastHarvest() == balanceOfWantStrategy
    assert vault.lifeTimeEarned() == 1e18
    print("Harvest time: ", vault.lastHarvestedAt)

    # Total supply should increase as we are minting shares to strategist and governance, if their respective fees are set
    assert total_supply_after_harvest - total_supply_before_harvest == feeGovernance + feeStrategist

    # pricePerFullShare should be dilluted if fees are set
    assert pricePerFullShare_before_harvest >= pricePerFullShare_after_harvest

def test_multiple_reports(setup_report, deployer, governance):

    vault = setup_report.vault
    strategy = setup_report.strategy
    want = setup_report.want

    feeGovernance = (1e18 * strategy.performanceFeeGovernance()) / MAX_BPS
    feeStrategist = (1e18 * strategy.performanceFeeStrategist()) / MAX_BPS
    balanceOfWantStrategy = strategy.balanceOfWant()
    total_supply_before_harvest = vault.totalSupply()

    strategy.test_harvest({"from": governance})

    assert vault.lastHarvestAmount() == 1e18
    assert vault.assetsAtLastHarvest() == balanceOfWantStrategy
    assert vault.lifeTimeEarned() == 1e18
    print("Harvest time: ", vault.lastHarvestedAt)

    # Mint some more want to the strategy to represent 2nd harvest
    mint_amount = 1e18
    want.mint(strategy, mint_amount)

    balanceOfWantStrategy = strategy.balanceOfWant()

    strategy.test_harvest({"from": governance})

    total_supply_after_harvest = vault.totalSupply()

    assert vault.lastHarvestAmount() == 1e18
    assert vault.assetsAtLastHarvest() == balanceOfWantStrategy
    assert vault.lifeTimeEarned() == 2e18
    print("Harvest time: ", vault.lastHarvestedAt)

    # Difference should be twice the fees as we have harvested twice
    assert total_supply_after_harvest - total_supply_before_harvest == 2 * (feeGovernance + feeStrategist)
