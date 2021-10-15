Badger Vaults 1.5
A linear improvement from original architecture

No longer using Controller

Just Vault and Strat

With Hooks for Deposits to rewards contract

## Changes / Gotchas
-> Strategy.withdrawAll to move all funds to the Vault
-> Vault.withdrawAll to move all funds to the Vault


## Vault.sol

Tracks shares for deposits
Tracks it's active `strategy`
Deposits and invests in strategy via `earn`
Allows to withdraw

### Breaking Changes
- Added `withdrawToVault`


## BaseStrategy.sol

### Breaking Changes
- `withdrawToVault` in stead of `withdrawAll()`

## Tests
<img width="1339" alt="Screenshot 2021-10-15 at 8 25 07 PM" src="https://user-images.githubusercontent.com/31198893/137511387-e667fe81-c368-4b61-a7e2-5c1b15c03dd7.png">


#### Test Coverage
<img width="681" alt="Screenshot 2021-10-15 at 8 30 14 PM" src="https://user-images.githubusercontent.com/31198893/137511398-a07b7431-920a-4d90-a8b4-317b7c5ddd4b.png">


## TODO

### Tests - Vault
test for initialize

pause

unpause


deposit / withdraw math
deposit / earn / withdraw math
deposit / earn / harvest withdraw math

deposit with authorization


setStrategy interaction

### Tests - Strategy

balanceOf()

setGuardian
setWithdrawalFee
setPerformanceFeeStrategist
setPerformanceFeeGovernance
setVault
setWithdrawalMaxDeviationThreshold





## TODO TODO Vault
trackFullPricePerShare() external whenNotPaused {
_lockForBlock
approveContractAccess

Rewards Contract integration
Deposit Hook to warn the rewards contract

## TODO TODO Strategy

_processFee

_withdrawAll
_withdrawSome

