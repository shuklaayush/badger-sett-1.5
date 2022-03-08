import brownie
from brownie import Vault

from helpers.constants import AddressZero


def test_setTreasury(deployed_vault, governance, randomUser):

    # setting treasury address
    deployed_vault.setTreasury(deployed_vault, {"from": governance})

    assert deployed_vault.treasury() == deployed_vault.address

    # setTreasury from random user should fail
    with brownie.reverts():
        deployed_vault.setTreasury(deployed_vault, {"from": randomUser})

    with brownie.reverts("Address 0"):
        deployed_vault.setTreasury(AddressZero, {"from": governance})


def test_setGuestList(deployed_gueslist, governance, randomUser):

    vault = deployed_gueslist.vault
    guestlist = deployed_gueslist.guestlist

    # setting guestlist address
    vault.setGuestList(guestlist, {"from": governance})

    assert vault.guestList() == guestlist.address

    # setGuestList from random user should fail
    with brownie.reverts():
        vault.setGuestList(guestlist, {"from": randomUser})


def test_setGuardian(deployed_vault, deployer, governance, randomUser):

    # setting address(0) should revert
    with brownie.reverts("Address cannot be 0x0"):
        deployed_vault.setGuardian(AddressZero, {"from": governance})

    # setting guardian address
    deployed_vault.setGuardian(randomUser, {"from": governance})

    assert deployed_vault.guardian() == randomUser

    # setGuardian from random user should fail
    with brownie.reverts():
        deployed_vault.setGuardian(randomUser, {"from": deployer})


def test_setMin(deployed_vault, governance, randomUser):

    # setting min > MAX should revert
    with brownie.reverts("toEarnBps should be <= MAX_BPS"):
        deployed_vault.setToEarnBps(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting min
    deployed_vault.setToEarnBps(1_000, {"from": governance})

    assert deployed_vault.toEarnBps() == 1_000

    # setting min from random user should fail
    with brownie.reverts():
        deployed_vault.setToEarnBps(1_000, {"from": randomUser})


def test_setMaxPerformanceFee(deployed_vault, governance, strategist, randomUser):

    # setting maxPeformanceFees > MAX should fail
    with brownie.reverts("performanceFeeStrategist too high"):
        deployed_vault.setMaxPerformanceFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting min
    deployed_vault.setMaxPerformanceFee(3_000, {"from": governance})

    assert deployed_vault.maxPerformanceFee() == 3_000

    # setting maxPeformanceFees from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxPerformanceFee(1_000, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxPerformanceFee(1_000, {"from": strategist})


def test_setMaxWithdrawalFee(deployed_vault, governance, strategist, randomUser):

    # setting maxWithdrawalFee > MAX should fail
    with brownie.reverts("withdrawalFee too high"):
        deployed_vault.setMaxWithdrawalFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting setMaxWithdrawalFee
    deployed_vault.setMaxWithdrawalFee(100, {"from": governance})

    assert deployed_vault.maxWithdrawalFee() == 100

    # setting setMaxWithdrawalFee from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxWithdrawalFee(100, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxWithdrawalFee(100, {"from": strategist})


def test_setMaxManagementFee(deployed_vault, governance, strategist, randomUser):

    # setting maxManagementFee > MAX should fail
    with brownie.reverts("managementFee too high"):
        deployed_vault.setMaxManagementFee(
            deployed_vault.MAX_BPS() + 1_000, {"from": governance}
        )

    # setting setMaxWithdrawalFee
    deployed_vault.setMaxManagementFee(150, {"from": governance})

    assert deployed_vault.maxManagementFee() == 150

    # setting setMaxWithdrawalFee from randomUser user / strategist should fail
    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxManagementFee(200, {"from": randomUser})

    with brownie.reverts("onlyGovernance"):
        deployed_vault.setMaxManagementFee(200, {"from": strategist})


def test_setManagementFee(deployed_vault, governance, strategist, randomUser):

    # setting managementFee
    deployed_vault.setManagementFee(100, {"from": governance})

    assert deployed_vault.managementFee() == 100

    # setting managementFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setManagementFee(5_000, {"from": randomUser})

    # setting more that maxManagementFee should fail
    with brownie.reverts("Excessive management fee"):
        deployed_vault.setManagementFee(
            2 * deployed_vault.maxManagementFee(), {"from": strategist}
        )


def test_setWithdrawalFee(deployed_vault, governance, strategist, randomUser):

    withdrawalFee = 100

    # withdrawalFee from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setWithdrawalFee(withdrawalFee, {"from": randomUser})

    # setting withdrawalFee
    deployed_vault.setWithdrawalFee(withdrawalFee, {"from": governance})

    assert deployed_vault.withdrawalFee() == withdrawalFee

    # setting more that maxWithdrawalFee should fail
    with brownie.reverts("Excessive withdrawal fee"):
        deployed_vault.setWithdrawalFee(
            2 * deployed_vault.maxWithdrawalFee(), {"from": strategist}
        )


def test_setPerformanceFeeStrategist(
    deployed_vault, governance, strategist, randomUser
):

    performanceFeeStrategist = 2_000  # increasing fees to compensate good strategist.

    # setPerformanceFeeStrategist from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setPerformanceFeeStrategist(
            performanceFeeStrategist, {"from": randomUser}
        )

    # setPerformanceFeeStrategist from governance
    deployed_vault.setPerformanceFeeStrategist(
        performanceFeeStrategist, {"from": governance}
    )

    # setPerformanceFeeStrategist from strategist
    deployed_vault.setPerformanceFeeStrategist(
        performanceFeeStrategist, {"from": strategist}
    )

    assert deployed_vault.performanceFeeStrategist() == performanceFeeStrategist

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("Excessive strategist performance fee"):
        deployed_vault.setPerformanceFeeStrategist(
            2 * deployed_vault.maxPerformanceFee(), {"from": strategist}
        )


def test_setPerformanceFeeGovernance(
    deployed_vault, governance, strategist, randomUser
):

    performanceFeeGovernance = 2_000

    # setPerformanceFeeGovernance from random user should fail
    with brownie.reverts("onlyGovernanceOrStrategist"):
        deployed_vault.setPerformanceFeeGovernance(
            performanceFeeGovernance, {"from": randomUser}
        )

    # setPerformanceFeeGovernance from governance
    deployed_vault.setPerformanceFeeGovernance(
        performanceFeeGovernance, {"from": governance}
    )

    # setPerformanceFeeGovernance from strategist
    deployed_vault.setPerformanceFeeGovernance(
        performanceFeeGovernance, {"from": strategist}
    )

    assert deployed_vault.performanceFeeGovernance() == performanceFeeGovernance

    # setting more that maxPerformanceFee should fail
    with brownie.reverts("Excessive governance performance fee"):
        deployed_vault.setPerformanceFeeGovernance(
            2 * deployed_vault.maxPerformanceFee(), {"from": strategist}
        )


def test_config_pause_unpause(deployed_vault, governance, strategist, randomUser):

    # Pause Vault
    deployed_vault.pause({"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setStrategy(randomUser, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setGuestList(randomUser, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setToEarnBps(100, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setManagementFee(1_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeGovernance(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setPerformanceFeeStrategist(2_000, {"from": governance})

    with brownie.reverts("Pausable: paused"):
        deployed_vault.setWithdrawalFee(100, {"from": governance})

    # unpause Vault, now we should be able to set everything
    deployed_vault.unpause({"from": governance})
    deployed_vault.setStrategy(randomUser, {"from": governance})
    deployed_vault.setGuestList(randomUser, {"from": governance})
    deployed_vault.setToEarnBps(100, {"from": governance})
    deployed_vault.setGuardian(randomUser, {"from": governance})
    deployed_vault.setMaxPerformanceFee(2_000, {"from": governance})
    deployed_vault.setMaxWithdrawalFee(50, {"from": governance})
    deployed_vault.setMaxManagementFee(150, {"from": governance})
    deployed_vault.setManagementFee(150, {"from": strategist})
    deployed_vault.setPerformanceFeeGovernance(2_000, {"from": strategist})
    deployed_vault.setPerformanceFeeStrategist(2_000, {"from": strategist})
    deployed_vault.setWithdrawalFee(50, {"from": strategist})

    with brownie.reverts("Pausable: not paused"):
        deployed_vault.unpause({"from": governance})
