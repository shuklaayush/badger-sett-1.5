import brownie
from brownie import *
from helpers.constants import MaxUint256, AddressZero

from dotmap import DotMap
import pytest


@pytest.fixture
def deposit_setup(deploy_complete, deployer, governance):

    want = deploy_complete.want
    vault = deploy_complete.vault

    # Deposit
    assert want.balanceOf(deployer) > 0

    # no balance in vault
    assert vault.balance() == 0

    # no inital shares of deployer
    assert vault.balanceOf(deployer) == 0

    depositAmount = int(want.balanceOf(deployer) * 0.01)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    return DotMap(deployed_vault=vault, want=want, depositAmount=depositAmount)


def test_deposit(deposit_setup, deployer, governance):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want
    depositAmount = deposit_setup.depositAmount

    # Test basic deposit
    balance_before_deposit = vault.balance()

    vault.deposit(depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount

    with brownie.reverts("Amount 0"):
        vault.deposit(0, {"from": deployer})

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.deposit(depositAmount, {"from": deployer})

    vault.unpause({"from": governance})

    assert vault.paused() == False

    # Test deposit when deposits are paused
    vault.pauseDeposits({"from": governance})

    assert vault.pausedDeposit() == True

    with brownie.reverts("pausedDeposit"):
        vault.deposit(depositAmount, {"from": deployer})

    vault.unpauseDeposits({"from": governance})


def test_depositFor(deposit_setup, deployer, governance, randomUser):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want
    depositAmount = deposit_setup.depositAmount

    # Test depositFor randomUser user
    balance_before_deposit = vault.balance()

    vault.depositFor(randomUser, depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount
    # check if balance is deposited for randomUser
    assert vault.balanceOf(randomUser) == depositAmount

    with brownie.reverts("Address 0"):
        vault.depositFor(AddressZero, depositAmount, {"from": deployer})

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.depositFor(randomUser, depositAmount, {"from": deployer})


def test_depositWithAuthorization(
    deployed_gueslist, deployer, governance, randomUser, randomUser2
):
    vault = deployed_gueslist.vault
    guestlist = deployed_gueslist.guestlist
    want = deployed_gueslist.want
    depositAmount = int(want.balanceOf(deployer) * 0.01)

    # # Test deposit for deployer who is whitelisted
    balance_before_deposit = vault.balance()

    want.approve(vault.address, MaxUint256, {"from": deployer})

    # cannot deposit more than userCap
    with brownie.reverts("GuestList: Not Authorized"):
        vault.deposit(3e18, {"from": deployer})

    # deployer is whitelisted so can deposit and depositAmount < userCap
    vault.deposit(depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount

    # randomUser cannot deposit
    want.approve(vault.address, MaxUint256, {"from": randomUser})
    with brownie.reverts("GuestList: Not Authorized"):
        vault.deposit(depositAmount, {"from": randomUser})


def test_depositForWithAuthorization(
    deployed_gueslist, deployer, governance, randomUser, randomUser2
):
    vault = deployed_gueslist.vault
    guestlist = deployed_gueslist.guestlist
    want = deployed_gueslist.want
    depositAmount = int(want.balanceOf(deployer) * 0.01)

    # # Test depositFor deployer who is whitelisted
    balance_before_deposit = vault.balance()

    want.approve(vault.address, MaxUint256, {"from": deployer})

    # cannot deposit more than userCap
    with brownie.reverts("GuestList: Not Authorized"):
        vault.depositFor(deployer, 3e18, {"from": deployer})

    # deployer is whitelisted so can deposit and depositAmount < userCap
    vault.depositFor(deployer, depositAmount, {"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount

    # depositFor where recipient is not whitelisted should fail
    with brownie.reverts("GuestList: Not Authorized"):
        vault.depositFor(randomUser, depositAmount, {"from": deployer})

    # # depositFor where recipient is whitelisted should work
    balance_before_deposit = vault.balance()
    vault.depositFor(randomUser2, depositAmount, {"from": deployer})
    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount

    assert vault.balanceOf(randomUser2) == depositAmount


def test_depositAll(deposit_setup, deployer, governance):
    vault = deposit_setup.deployed_vault
    want = deposit_setup.want

    depositAmount = want.balanceOf(deployer)

    # Test depositAll
    balance_before_deposit = vault.balance()

    vault.depositAll({"from": deployer})

    balance_after_deposit = vault.balance()

    assert balance_after_deposit - balance_before_deposit == depositAmount

    # Test deposit when vault is paused
    vault.pause({"from": governance})

    assert vault.paused() == True

    with brownie.reverts("Pausable: paused"):
        vault.depositAll({"from": deployer})


def test_nonreentrant(
    deployer, governance, keeper, guardian, strategist, badgerTree, randomUser
):
    token = MaliciousToken.deploy({"from": deployer})
    token.initialize(
        [deployer.address, randomUser.address], [100 * 10 ** 18, 100 * 10 ** 18]
    )

    # NOTE: change strategist
    vault = Vault.deploy({"from": deployer})
    vault.initialize(
        token,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
        "",
        "",
        [
            0,
            0,
            0,
            0,
        ],
    )

    strategy = DemoStrategy.deploy({"from": deployer})
    strategy.initialize(vault, [token])

    vault.setStrategy(strategy, {"from": governance})

    depositAmount = token.balanceOf(deployer)

    with brownie.reverts("ReentrancyGuard: reentrant call"):
        vault.deposit(depositAmount, {"from": deployer})
