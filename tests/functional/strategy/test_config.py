import brownie
from brownie import *

from helpers.constants import AddressZero


def test_setWithdrawalMaxDeviationThreshold(deploy_complete, governance, randomUser):

    strategy = deploy_complete.strategy
    withdrawalMaxDeviationThreshold = 100

    # withdrawalMaxDeviationThreshold from random user should fail
    with brownie.reverts("onlyGovernance"):
        strategy.setWithdrawalMaxDeviationThreshold(
            withdrawalMaxDeviationThreshold, {"from": randomUser}
        )

    # setting withdrawalMaxDeviationThreshold
    strategy.setWithdrawalMaxDeviationThreshold(
        withdrawalMaxDeviationThreshold, {"from": governance}
    )

    assert strategy.withdrawalMaxDeviationThreshold() == withdrawalMaxDeviationThreshold

    # setting more that MAX should fail
    with brownie.reverts("base-strategy/excessive-max-deviation-threshold"):
        strategy.setWithdrawalMaxDeviationThreshold(
            2 * strategy.MAX_BPS(), {"from": governance}
        )

def test_isProtectedToken(deploy_complete, deployer):
    strategy = deploy_complete.strategy

    with brownie.reverts("Address 0"):
        strategy.isProtectedToken(AddressZero)

    assert strategy.isProtectedToken(strategy.want()) == True

    token = MockToken.deploy({"from": deployer})

    assert strategy.isProtectedToken(token) == False
