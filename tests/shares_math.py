import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

## Test for deposit with no initial shares
def test_deposit_no_initial_shares(
    deployer, vault, strategy, want, settKeeper
):
    assert True

## Test for deposit with some initial shares

## Test for deposit with some initial + an harvest, checks ppfs changes and see if it works as intended

## Test for withdrawal given shares

## Test for withdrawal after harvest

## Test for multiple withdrawals