import brownie
from brownie import *

from helpers.constants import AddressZero


def test_empty_deposit(deploy_complete, keeper):
    strategy = deploy_complete.strategy

    assert strategy.balance() == 0

    strategy.deposit({"from": keeper})

    assert strategy.balance() == 0
