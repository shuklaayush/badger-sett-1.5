import brownie
from brownie import *

from helpers.constants import AddressZero

## Test Permissioned actions
def test_setGuardian(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy

    # setRewards from random user should fail
    with brownie.reverts("onlyGovernance"): 
        strategy.setGuardian(rando, {"from": rando})

    # setting rewards address
    strategy.setGuardian(rando, {"from": governance})

    assert strategy.guardian() == rando

def test_setWithdrawalFee(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy
    withdrawalFee = 100

    # withdrawalFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        strategy.setWithdrawalFee(withdrawalFee, {"from": rando})

    # setting withdrawalFee
    strategy.setWithdrawalFee(withdrawalFee, {"from": governance})

    assert strategy.withdrawalFee() == withdrawalFee

    # setting more that MAX_FEE should fail
    with brownie.reverts("base-strategy/excessive-withdrawal-fee"):
        strategy.setWithdrawalFee(2 * strategy.MAX_FEE(), {"from": governance})

def test_setPerformanceFeeStrategist(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy
    performanceFeeStrategist = 2000 # Good Strategist become have more rare therefore to compensate them more

    # setPerformanceFeeStrategist from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        strategy.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": rando})

    # setting setPerformanceFeeStrategist
    strategy.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": governance})

    assert strategy.performanceFeeStrategist() == performanceFeeStrategist

    # setting more that MAX_FEE should fail
    with brownie.reverts("base-strategy/excessive-strategist-performance-fee"):
        strategy.setPerformanceFeeStrategist(2 * strategy.MAX_FEE(), {"from": governance})

def test_setPerformanceFeeGovernance(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy
    performanceFeeGovernance = 2000 # Good Strategist become have more rare therefore to compensate them more

    # setPerformanceFeeGovernance from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"): 
        strategy.setPerformanceFeeGovernance(performanceFeeGovernance, {"from": rando})

    # setting setPerformanceFeeGovernance
    strategy.setPerformanceFeeGovernance(performanceFeeGovernance, {"from": governance})

    assert strategy.performanceFeeGovernance() == performanceFeeGovernance

    # setting more that MAX_FEE should fail
    with brownie.reverts("base-strategy/excessive-governance-performance-fee"):
        strategy.setPerformanceFeeGovernance(2 * strategy.MAX_FEE(), {"from": governance})

def test_setVault(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy

    # setVault from random user should fail
    with brownie.reverts("onlyGovernance"): 
        strategy.setVault(rando, {"from": rando})

    # setting vault address
    strategy.setVault(rando, {"from": governance})

    assert strategy.vault() == rando

def test_setWithdrawalMaxDeviationThreshold(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy
    withdrawalMaxDeviationThreshold = 100

    # withdrawalMaxDeviationThreshold from random user should fail
    with brownie.reverts("onlyGovernance"): 
        strategy.setWithdrawalMaxDeviationThreshold(withdrawalMaxDeviationThreshold, {"from": rando})

    # setting withdrawalMaxDeviationThreshold
    strategy.setWithdrawalMaxDeviationThreshold(withdrawalMaxDeviationThreshold, {"from": governance})

    assert strategy.withdrawalMaxDeviationThreshold() == withdrawalMaxDeviationThreshold

    # setting more that MAX_FEE should fail
    with brownie.reverts("base-strategy/excessive-max-deviation-threshold"):
        strategy.setWithdrawalMaxDeviationThreshold(2 * strategy.MAX_FEE(), {"from": governance})
