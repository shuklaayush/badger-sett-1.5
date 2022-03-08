import brownie
from brownie import *
from helpers.constants import AddressZero, MaxUint256

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

    want.approve(vault.address, MaxUint256, {"from": deployer})

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


def setup_mint(strategy, token, mint_amount):
    # Mint additional tokens for strategy
    before_mint = token.balanceOf(strategy)
    token.mint(strategy, mint_amount)
    after_mint = token.balanceOf(strategy)
    assert after_mint - before_mint == mint_amount

    return mint_amount


def test_report_failed(
    vault, strategy, want, deployer, governance, randomUser, keeper, mint_amount
):
    depositAmount = int(want.balanceOf(deployer) * 0.1)
    assert depositAmount > 0

    # Deposit and earn
    vault.deposit(depositAmount, {"from": deployer})
    vault.earn({"from": governance})

    ## Report will work if Vault is paused (strat is active)
    # Pausing vault
    vault.pause({"from": governance})

    assert vault.paused() == True
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
        vault.reportHarvest(1e18, {"from": randomUser})

    # harvest should fail when called by randomUser
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.test_harvest(mint_amount, {"from": randomUser})


def test_harvest_no_balance(strategy, vault, keeper, want, mint_amount):
    strategy.test_empty_harvest({"from": keeper})
    assert vault.assetsAtLastHarvest() == 0

    setup_mint(strategy, want, mint_amount)

    strategy.test_harvest(mint_amount, {"from": keeper})
    assert vault.assetsAtLastHarvest() == 0


def test_report_additional_token_failed(
    vault, strategy, governance, want, deployer, randomUser, keeper, token, mint_amount
):
    depositAmount = int(want.balanceOf(deployer) * 0.1)
    assert depositAmount > 0

    # Deposit and earn
    vault.deposit(depositAmount, {"from": deployer})
    vault.earn({"from": governance})

    setup_mint(strategy, token, mint_amount)

    with brownie.reverts("Not want, use _reportToVault"):
        strategy.test_harvest_only_emit(want, mint_amount, {"from": keeper})

    with brownie.reverts("Address 0"):
        strategy.test_harvest_only_emit(AddressZero, mint_amount, {"from": keeper})

    # Creating another token
    with brownie.reverts("Amount 0"):
        strategy.test_harvest_only_emit(token, 0, {"from": keeper})

    ## report should fail when vault is paused
    # Pausing vault
    vault.pause({"from": governance})

    assert vault.paused() == True

    ## Harvest still works if you pause Vault
    strategy.test_harvest_only_emit(token, mint_amount, {"from": keeper})

    vault.unpause({"from": governance})

    ## report should fail when strategy is paused
    # Pausing strategy
    strategy.pause({"from": governance})

    assert strategy.paused() == True

    ## Harvest is paused if you pause Strat
    with brownie.reverts("Pausable: paused"):
        strategy.test_harvest_only_emit(token, mint_amount, {"from": keeper})

    strategy.unpause({"from": governance})

    # report should fail report function is not called from strategy
    with brownie.reverts("onlyStrategy"):
        vault.reportAdditionalToken(token, {"from": randomUser})

    # should fail if trying to report want as additional token
    with brownie.reverts("No want"):
        vault.reportAdditionalToken(vault.token(), {"from": strategy})

    # harvest should fail when called by randomUser
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.test_harvest_only_emit(token, mint_amount, {"from": randomUser})
