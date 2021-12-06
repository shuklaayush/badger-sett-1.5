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
        vault.reportHarvest(1e18, {"from": rando})

    # harvest should fail when called by rando
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.test_harvest(mint_amount, {"from": rando})
