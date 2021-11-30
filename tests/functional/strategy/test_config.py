import brownie
from brownie import *

from helpers.constants import AddressZero


def test_setWithdrawalMaxDeviationThreshold(deploy_complete, governance, rando):

    strategy = deploy_complete.strategy
    withdrawalMaxDeviationThreshold = 100

    # withdrawalMaxDeviationThreshold from random user should fail
    with brownie.reverts("onlyGovernance"):
        strategy.setWithdrawalMaxDeviationThreshold(
            withdrawalMaxDeviationThreshold, {"from": rando}
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
