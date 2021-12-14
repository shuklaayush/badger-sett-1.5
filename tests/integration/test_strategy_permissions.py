import brownie
from brownie import *
from helpers.constants import MaxUint256, AddressZero
from helpers.time import days


def state_setup(deployer, sett, vault, strategy, want):
    startingBalance = want.balanceOf(deployer)

    settKeeper = accounts.at(vault.keeper(), force=True)
    strategyKeeper = accounts.at(strategy.keeper(), force=True)

    tendable = strategy.isTendable()

    startingBalance = want.balanceOf(deployer)
    depositAmount = int(startingBalance * 0.8)
    assert startingBalance >= depositAmount

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    chain.sleep(days(1))
    chain.mine()

    vault.earn({"from": settKeeper})

    chain.sleep(days(1))
    chain.mine()

    if tendable:
        strategy.tend({"from": strategyKeeper})

    strategy.harvest({"from": strategyKeeper})

    chain.sleep(days(1))
    chain.mine()

    accounts.at(deployer, force=True)
    accounts.at(strategy.strategist(), force=True)
    accounts.at(strategy.keeper(), force=True)
    accounts.at(strategy.guardian(), force=True)
    accounts.at(vault, force=True)


def test_strategy_action_permissions(deployer, vault, strategy, want):
    state_setup(deployer, vault, vault, strategy, want)

    tendable = strategy.isTendable()

    randomUser = accounts[8]
    # End Setup

    # ===== Strategy =====
    authorizedActors = [
        strategy.governance(),
        strategy.keeper(),
    ]

    with brownie.reverts("onlyAuthorizedActorsOrVault"):
        strategy.deposit({"from": randomUser})

    for actor in authorizedActors:
        strategy.deposit({"from": actor})

    # harvest: onlyAuthorizedActors
    with brownie.reverts("onlyAuthorizedActors"):
        strategy.harvest({"from": randomUser})

    for actor in authorizedActors:
        chain.sleep(10000 * 13)  ## 10k blocks per harvest
        strategy.harvest({"from": actor})

    # (if tendable) tend: onlyAuthorizedActors
    if tendable:
        with brownie.reverts("onlyAuthorizedActors"):
            strategy.tend({"from": randomUser})

        for actor in authorizedActors:
            strategy.tend({"from": actor})

    actorsToCheck = [
        randomUser.address,
        strategy.governance(),
        strategy.strategist(),
        strategy.keeper(),
    ]

    # withdrawToVault onlyVault
    for actor in actorsToCheck:
        if actor == strategy.governance() or actor == strategy.strategist():
            vault.withdrawToVault({"from": actor})
        else:
            with brownie.reverts("onlyGovernanceOrStrategist"):
                vault.withdrawToVault({"from": actor})

    # withdraw onlyVault
    for actor in actorsToCheck:
        with brownie.reverts("onlyVault"):
            strategy.withdraw(1, {"from": actor})

    # withdrawOther _onlyNotProtectedTokens
    for actor in actorsToCheck:
        if actor == strategy.governance() or actor == strategy.strategist():
            vault.sweepExtraToken(vault, {"from": actor})
        else:
            with brownie.reverts("onlyGovernanceOrStrategist"):
                vault.sweepExtraToken(vault, {"from": actor})


def test_strategy_pausing_permissions(deployer, vault, strategy, want):
    # Setup
    state_setup(deployer, vault, vault, strategy, want)
    randomUser = accounts[8]
    # End Setup

    authorizedPausers = [
        strategy.governance(),
        strategy.guardian(),
    ]

    authorizedUnpausers = [
        strategy.governance(),
    ]

    # pause onlyPausers
    for pauser in authorizedPausers:
        strategy.pause({"from": pauser})
        strategy.unpause({"from": authorizedUnpausers[0]})

    with brownie.reverts("onlyPausers"):
        strategy.pause({"from": randomUser})

    # unpause onlyPausers
    for unpauser in authorizedUnpausers:
        strategy.pause({"from": unpauser})
        strategy.unpause({"from": unpauser})

    with brownie.reverts("onlyGovernance"):
        strategy.unpause({"from": randomUser})

    strategy.pause({"from": strategy.guardian()})

    strategyKeeper = accounts.at(strategy.keeper(), force=True)

    with brownie.reverts("Pausable: paused"):
        strategy.harvest({"from": strategyKeeper})
    if strategy.isTendable():
        with brownie.reverts("Pausable: paused"):
            strategy.tend({"from": strategyKeeper})

    strategy.unpause({"from": authorizedUnpausers[0]})

    vault.deposit(1, {"from": deployer})
    vault.withdraw(1, {"from": deployer})
    vault.withdrawAll({"from": deployer})

    strategy.harvest({"from": strategyKeeper})
    if strategy.isTendable():
        strategy.tend({"from": strategyKeeper})


def test_sett_pausing_permissions(deployer, vault, strategy, want):
    # Setup
    state_setup(deployer, vault, vault, strategy, want)
    randomUser = accounts[8]
    # End Setup

    authorizedPausers = [
        vault.governance(),
        vault.guardian(),
    ]

    authorizedUnpausers = [
        vault.governance(),
    ]

    # pause onlyPausers
    for pauser in authorizedPausers:
        vault.pause({"from": pauser})
        vault.unpause({"from": authorizedUnpausers[0]})

    with brownie.reverts("onlyPausers"):
        vault.pause({"from": randomUser})

    # unpause onlyPausers
    for unpauser in authorizedUnpausers:
        vault.pause({"from": unpauser})
        vault.unpause({"from": unpauser})

    vault.pause({"from": vault.guardian()})
    with brownie.reverts("onlyGovernance"):
        vault.unpause({"from": randomUser})

    settKeeper = accounts.at(vault.keeper(), force=True)

    with brownie.reverts("Pausable: paused"):
        vault.earn({"from": settKeeper})
    with brownie.reverts("Pausable: paused"):
        vault.withdrawAll({"from": deployer})
    with brownie.reverts("Pausable: paused"):
        vault.withdraw(1, {"from": deployer})
    with brownie.reverts("Pausable: paused"):
        vault.deposit(1, {"from": randomUser})
    with brownie.reverts("Pausable: paused"):
        vault.depositAll({"from": randomUser})

    vault.unpause({"from": authorizedUnpausers[0]})

    vault.deposit(1, {"from": deployer})
    vault.earn({"from": settKeeper})
    vault.withdraw(1, {"from": deployer})
    vault.withdrawAll({"from": deployer})


def test_sett_config_permissions(deployer, vault, strategy, want):
    state_setup(deployer, vault, vault, strategy, want)
    randomUser = accounts[8]
    # End Setup

    # == Governance ==
    validActor = vault.governance()

    # setMin
    with brownie.reverts("onlyGovernance"):
        vault.setToEarnBps(0, {"from": randomUser})

    vault.setToEarnBps(0, {"from": validActor})
    assert vault.toEarnBps() == 0

    # setStrategy
    with brownie.reverts("onlyGovernance"):
        vault.setStrategy(AddressZero, {"from": randomUser})

    if strategy.balanceOf() == 0:
        vault.setStrategy(AddressZero, {"from": validActor})
    else:
        with brownie.reverts():
            vault.setStrategy(AddressZero, {"from": validActor})
        vault.withdrawAll({"from": deployer})
        vault.setStrategy(AddressZero, {"from": validActor})

    assert vault.strategy() == AddressZero

    # setStrategist
    with brownie.reverts("onlyGovernance"):
        vault.setStrategist(validActor, {"from": randomUser})

    vault.setStrategist(validActor, {"from": validActor})
    assert vault.strategist() == validActor

    with brownie.reverts("onlyGovernance"):
        vault.setKeeper(validActor, {"from": randomUser})

    vault.setKeeper(validActor, {"from": validActor})
    assert vault.keeper() == validActor


def test_sett_earn_permissions(deployer, vault, strategy, want):
    # Setup
    state_setup(deployer, vault, vault, strategy, want)
    randomUser = accounts[8]
    # End Setup

    # == Authorized Actors ==
    # earn

    authorizedActors = [
        vault.governance(),
        vault.keeper(),
    ]

    with brownie.reverts("onlyAuthorizedActors"):
        vault.earn({"from": randomUser})

    for actor in authorizedActors:
        chain.snapshot()
        vault.earn({"from": actor})
        chain.revert()
