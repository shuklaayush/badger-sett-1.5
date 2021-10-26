import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days


def test_deposit_withdraw_single_user_flow(deployer, vault, strategy, want, settKeeper):
    # Setup
    snap = SnapshotManager(vault, strategy, "StrategySnapshot")
    randomUser = accounts[6]
    # End Setup

    # Deposit
    assert want.balanceOf(deployer) > 0

    depositAmount = int(want.balanceOf(deployer) * 0.8)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    vault.deposit(depositAmount, {"from": deployer})

    shares = vault.balanceOf(deployer)

    # Earn
    with brownie.reverts("onlyAuthorizedActors"):
        vault.earn({"from": randomUser})

    snap.settEarn({"from": settKeeper})

    chain.sleep(15)
    chain.mine(1)

    snap.settWithdraw(shares // 2, {"from": deployer})

    chain.sleep(10000)
    chain.mine(1)

    snap.settWithdraw(shares // 2 - 1, {"from": deployer})


def test_single_user_harvest_flow(
    deployer, vault, strategy, want, settKeeper, strategyKeeper
):
    # Setup
    snap = SnapshotManager(vault, strategy, "StrategySnapshot")
    randomUser = accounts[6]
    tendable = strategy.isTendable()
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup

    # Deposit
    want.approve(vault, MaxUint256, {"from": deployer})
    snap.settDeposit(depositAmount, {"from": deployer})
    shares = vault.balanceOf(deployer)

    assert want.balanceOf(vault) > 0
    print("want.balanceOf(vault)", want.balanceOf(vault))

    # Earn
    snap.settEarn({"from": settKeeper})

    if tendable:
        with brownie.reverts("onlyAuthorizedActors"):
            strategy.tend({"from": randomUser})

        snap.settTend({"from": strategyKeeper})

    chain.sleep(days(0.5))
    chain.mine()

    if tendable:
        snap.settTend({"from": strategyKeeper})

    chain.sleep(days(1))
    chain.mine()

    with brownie.reverts("onlyAuthorizedActors"):
        strategy.harvest({"from": randomUser})

    snap.settHarvest({"from": strategyKeeper})

    chain.sleep(days(1))
    chain.mine()

    if tendable:
        snap.settTend({"from": strategyKeeper})

    snap.settWithdraw(shares // 2, {"from": deployer})

    chain.sleep(days(3))
    chain.mine()

    snap.settHarvest({"from": strategyKeeper})
    snap.settWithdraw(shares // 2 - 1, {"from": deployer})


def test_migrate_single_user(deployer, vault, strategy, want, strategist):
    # Setup
    randomUser = accounts[6]
    snap = SnapshotManager(vault, strategy, "StrategySnapshot")

    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    # End Setup

    # Deposit
    want.approve(vault, MaxUint256, {"from": deployer})
    snap.settDeposit(depositAmount, {"from": deployer})

    chain.sleep(15)
    chain.mine()

    vault.earn({"from": strategist})

    chain.snapshot()

    # Test no harvests
    chain.sleep(days(2))
    chain.mine()

    before = {"settWant": want.balanceOf(vault), "stratWant": strategy.balanceOf()}

    with brownie.reverts():
        vault.withdrawToVault({"from": randomUser})

    vault.withdrawToVault({"from": deployer})

    after = {"settWant": want.balanceOf(vault), "stratWant": strategy.balanceOf()}

    assert after["settWant"] > before["settWant"]
    assert after["stratWant"] < before["stratWant"]
    assert after["stratWant"] == 0

    # Test tend only
    if strategy.isTendable():
        chain.revert()

        chain.sleep(days(2))
        chain.mine()

        strategy.tend({"from": deployer})

        before = {"settWant": want.balanceOf(vault), "stratWant": strategy.balanceOf()}

        with brownie.reverts():
            vault.withdrawToVault({"from": randomUser})

        vault.withdrawToVault({"from": deployer})

        after = {"settWant": want.balanceOf(vault), "stratWant": strategy.balanceOf()}

        assert after["settWant"] > before["settWant"]
        assert after["stratWant"] < before["stratWant"]
        assert after["stratWant"] == 0

    # Test harvest, with tend if tendable
    chain.revert()

    chain.sleep(days(1))
    chain.mine()

    if strategy.isTendable():
        strategy.tend({"from": deployer})

    chain.sleep(days(1))
    chain.mine()

    before = {
        "settWant": want.balanceOf(vault),
        "stratWant": strategy.balanceOf(),
        "rewardsWant": want.balanceOf(vault.rewards()),
    }

    with brownie.reverts():
        vault.withdrawToVault({"from": randomUser})

    vault.withdrawToVault({"from": deployer})

    after = {"settWant": want.balanceOf(vault), "stratWant": strategy.balanceOf()}

    assert after["settWant"] > before["settWant"]
    assert after["stratWant"] < before["stratWant"]
    assert after["stratWant"] == 0


def test_withdraw_other(deployer, vault, strategy, want):
    """
    - Vault should be able to withdraw other tokens
    - Vault should not be able to withdraw core/protected tokens
    """
    # Setup
    randomUser = accounts[6]
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    # End Setup

    # Deposit
    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    chain.sleep(15)
    chain.mine()

    vault.earn({"from": deployer})

    chain.sleep(days(0.5))
    chain.mine()

    if strategy.isTendable():
        strategy.tend({"from": deployer})

    strategy.harvest({"from": deployer})

    chain.sleep(days(0.5))
    chain.mine()

    mockAmount = Wei("1000 ether")
    mockToken = MockToken.deploy({"from": deployer})
    mockToken.initialize([strategy], [mockAmount], {"from": deployer})

    assert mockToken.balanceOf(strategy) == mockAmount

    # Should not be able to withdraw protected tokens
    protectedTokens = strategy.getProtectedTokens()

    for token in protectedTokens:
        with brownie.reverts():
            vault.sweepExtraToken(strategy, token, {"from": deployer})

    # Should send balance of non-protected token to sender
    vault.sweepExtraToken(strategy, mockToken, {"from": deployer})

    # Only Strategist/Goverance should be able to withdraw other tokens
    with brownie.reverts():
        vault.sweepExtraToken(strategy, mockToken, {"from": randomUser})

    assert mockToken.balanceOf(vault) == mockAmount


def test_single_user_harvest_flow_remove_fees(deployer, vault, strategy, want):
    # Setup
    randomUser = accounts[6]
    snap = SnapshotManager(vault, strategy, "StrategySnapshot")
    startingBalance = want.balanceOf(deployer)
    tendable = strategy.isTendable()
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    # End Setup

    # Deposit
    want.approve(vault, MaxUint256, {"from": deployer})
    snap.settDeposit(depositAmount, {"from": deployer})

    # Earn
    snap.settEarn({"from": deployer})

    chain.sleep(days(0.5))
    chain.mine()

    if tendable:
        snap.settTend({"from": deployer})

    chain.sleep(days(1))
    chain.mine()

    with brownie.reverts("onlyAuthorizedActors"):
        strategy.harvest({"from": randomUser})

    snap.settHarvest({"from": deployer})

    ## NOTE: Some strats do not do this, change accordingly
    # assert want.balanceOf(vault.rewards()) > 0

    chain.sleep(days(1))
    chain.mine()

    if tendable:
        snap.settTend({"from": deployer})

    chain.sleep(days(3))
    chain.mine()

    snap.settHarvest({"from": deployer})

    snap.settWithdrawAll({"from": deployer})

    endingBalance = want.balanceOf(deployer)

    print("Report after 4 days")
    print("Gains")
    print(endingBalance - startingBalance)
    print("gainsPercentage")
    print((endingBalance - startingBalance) / startingBalance)
