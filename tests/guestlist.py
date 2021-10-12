import brownie
from brownie import *
from helpers.constants import MaxUint256, AddressZero
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

## Test where you add a guestlist, use proof for deposit
def test_add_guestlist(deployer, governance, randomUser, vault, guestlist, want):    
    # Adding deployer to guestlist
    guestlist.setGuests([deployer], [True], {"from": governance})

    # Sets guestlist on Vault (Requires Vault's governance)
    vault.setGuestList(guestlist.address, {"from": governance})
    
    depositAmount = 1e18 if want.balanceOf(deployer) > 1e18 else want.balanceOf(deployer)
    
    assert depositAmount != 0

    # Deposit
    want.approve(vault, MaxUint256, {"from": deployer})
    
    before_shares = want.balanceOf(vault)

    assert before_shares == 0
    
    vault.deposit(depositAmount, {"from": deployer})

    after_shares =  want.balanceOf(vault)

    assert after_shares == depositAmount

    # Deposit from user who is not in guestlist should fail
    want.approve(vault, MaxUint256, {"from": randomUser})
    depositAmount = 1e18 if want.balanceOf(randomUser) > 1e18 else want.balanceOf(randomUser)
    assert depositAmount != 0
    with brownie.reverts():
        vault.deposit(depositAmount, {"from": randomUser})

## Test where you add a guestlist, remove it and anyone can deposit

## Test with guestlist -> want Limit

## Test with guestlist -> user Limit

## TODO: Add guest list once we find compatible, tested, contract
# guestList = TestVipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
# guestList.initialize(sett, {"from": deployer})
# guestList.setGuests([deployer], [True])
# guestList.setUserDepositCap(100000000)
# sett.setGuestList(guestList, {"from": governance})

