import brownie
from brownie import *

from helpers.constants import AddressZero

# setPerformanceFeeStrategist
# setPerformanceFeeGovernance
# setVault
# setWithdrawalMaxDeviationThreshold

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
    with brownie.reverts("onlyGovernance"): 
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
    with brownie.reverts("onlyGovernance"): 
        strategy.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": rando})

    # setting setPerformanceFeeStrategist
    strategy.setPerformanceFeeStrategist(performanceFeeStrategist, {"from": governance})

    assert strategy.performanceFeeStrategist() == performanceFeeStrategist

    # setting more that MAX_FEE should fail
    with brownie.reverts("base-strategy/excessive-strategist-performance-fee"):
        strategy.setPerformanceFeeStrategist(2 * strategy.MAX_FEE(), {"from": governance})
