import brownie
from brownie import *
from helpers.constants import MaxUint256

from dotmap import DotMap
import pytest
import math

MAX_BPS = 10_000
SECS_PER_YEAR = 31_556_952


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

    return DotMap(
        vault=vault, strategy=strategy, want=want, depositAmount=depositAmount
    )


@pytest.fixture
def vault(setup_report):
    return setup_report.vault


@pytest.fixture
def strategy(setup_report):
    return setup_report.strategy


@pytest.fixture
def want(setup_report):
    return setup_report.want


@pytest.fixture
def depositAmount(setup_report):
    return setup_report.depositAmount


@pytest.fixture
def mint_amount():
    return 1e18

def setup_mint(strategy, want, mint_amount):
    ## Transfer some want to strategy which will represent harvest
    before_mint = strategy.balanceOf()
    want.mint(strategy, mint_amount)
    after_mint = strategy.balanceOf()
    assert after_mint - before_mint == mint_amount

    return mint_amount


def test_report_failed(vault, strategy, governance, rando, keeper, mint_amount):

    ## report should fail when vault is paused
    # Pausing vault
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        strategy.test_harvest(mint_amount, {"from": keeper})

    vault.unpause({"from": governance})

    ## report should fail when strategy is paused
    # Pausing strategy
    strategy.pause({"from": governance})

    assert strategy.paused() == True

    with brownie.reverts("Pausable: paused"):
        strategy.test_harvest(mint_amount, {"from": keeper})

    strategy.unpause({"from": governance})

    # report should fail report function is not called from strategy
    with brownie.reverts("onlyStrategy"):
        vault.report(1e18, {"from": rando})

    # harvest should fail when called by rando
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.test_harvest(mint_amount, {"from": rando})


def test_report(vault, strategy, want, deployer, governance, depositAmount, mint_amount):

    total_supply_before_harvest = vault.totalSupply()
    balanceBeforeHarvest = vault.balance()

    ### Harvesting and reporting

    # Sent 1 ether as want to strategy to represent harvest
    mintAmount = 1e18

    last_harvest_time = vault.lastHarvestedAt()

    feeGovernance = (mintAmount * vault.performanceFeeGovernance()) / MAX_BPS
    feeStrategist = (mintAmount * vault.performanceFeeStrategist()) / MAX_BPS
    

    setup_mint(strategy, want, mint_amount)

    pricePerFullShare_before_fees = vault.getPricePerFullShare()



    strategy.test_harvest(
        mint_amount,
        {"from": governance}
    )  # test_harvest to report harvest value to vault which will take respective fees

    management_fee = (
        (
            vault.balance()
            * vault.managementFee()
            * (vault.lastHarvestedAt() - last_harvest_time)
        )
        / MAX_BPS
        / SECS_PER_YEAR
    )

    total_supply_after_harvest = vault.totalSupply()
    pricePerFullShare_after_fees = vault.getPricePerFullShare()

    assert vault.lastHarvestAmount() == mintAmount
    assert vault.assetsAtLastHarvest() == balanceBeforeHarvest
    assert vault.lifeTimeEarned() == mintAmount
    print("Harvest time: ", vault.lastHarvestedAt())

    # Total supply should increase as we are minting shares to strategist and governance, if their respective fees are set
    assert total_supply_after_harvest >= total_supply_before_harvest

    earned_to_deposit_ratio = mintAmount / depositAmount

    # pricePerFullShare should be dilluted if fees are set, comparing with relative tolerance = 10^-9
    assert math.isclose(
        (pricePerFullShare_before_fees - pricePerFullShare_after_fees),
        (feeGovernance + feeStrategist + management_fee) * earned_to_deposit_ratio,
    )


def test_multiple_reports(vault, strategy, want, deployer, governance, depositAmount, mint_amount):

    total_supply_before_harvest = vault.totalSupply()
    balanceBeforeHarvest = vault.balance()

    ### Harvesting and reporting

    # Sent 1 ether as want to strategy to represent harvest
    mintAmount = 1e18

    last_harvest_time = vault.lastHarvestedAt()

    feeGovernance = (mintAmount * vault.performanceFeeGovernance()) / MAX_BPS
    feeStrategist = (mintAmount * vault.performanceFeeStrategist()) / MAX_BPS
    last_harvest_time = vault.lastHarvestedAt()

    mint_amount = setup_mint(strategy, want, mint_amount)

    # --

    pricePerFullShare_before_fees = vault.getPricePerFullShare()

    strategy.test_harvest(mint_amount, {"from": governance})

    management_fee = (
        (
            vault.balance()
            * vault.managementFee()
            * (vault.lastHarvestedAt() - last_harvest_time)
        )
        / MAX_BPS
        / SECS_PER_YEAR
    )

    pricePerFullShare_after_fees = vault.getPricePerFullShare()

    assert vault.lastHarvestAmount() == mintAmount
    assert vault.assetsAtLastHarvest() == balanceBeforeHarvest
    assert vault.lifeTimeEarned() == mintAmount
    print("Harvest time: ", vault.lastHarvestedAt())

    earned_to_deposit_ratio = mintAmount / depositAmount

    # pricePerFullShare should be dilluted if fees are set, comparing with relative tolerance = 10^-9
    assert math.isclose(
        (pricePerFullShare_before_fees - pricePerFullShare_after_fees),
        (feeGovernance + feeStrategist + management_fee) * earned_to_deposit_ratio,
    )

    balanceBeforeHarvest = vault.balance()

    # Mint some more want to the strategy to represent 2nd harvest

    setup_mint(strategy, want, mint_amount)

    # --

    pricePerFullShare_before_fees = vault.getPricePerFullShare()
    strategy.test_harvest(mint_amount, {"from": governance})

    total_supply_after_harvest = vault.totalSupply()
    pricePerFullShare_after_fees = vault.getPricePerFullShare()

    assert vault.lastHarvestAmount() == mintAmount
    assert vault.assetsAtLastHarvest() == balanceBeforeHarvest
    assert vault.lifeTimeEarned() == mintAmount * 2
    print("Harvest time: ", vault.lastHarvestedAt())

    # Total supply should increase as we are minting shares to strategist and governance, if their respective fees are set
    assert total_supply_after_harvest >= total_supply_before_harvest

    # pricePerFullShare should be dilluted if fees are set
    assert pricePerFullShare_before_fees > pricePerFullShare_after_fees
