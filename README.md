# Badger Vaults 1.5 - WARNING - CODE NOT AUDITED - WORK IN PROGRESS

A linear improvement from original architecture. No longer using Controller, just Vault and Strategy.

## TODO

- Test Pause
- Test Permissions
  Remove all the clutter from functional tests
  Bulk all permissions test separately

- Test Math
  -> Check it's all there


  TODO TODO TODO
  All the math for shares needs to be tested by re-doing the snapshot manager
  Also, migrate the math for shares to be used everywhere (in tests)

CHANGE
All withdrawal should be == not >=

> = means the vault is loosing money and the user is gaining
> We cannot socialize lossess

## Overview

### Vault

- Tracks shares for deposits
- Tracks it's active `strategy`
- Deposits and invests in strategy via `earn`
- Allows to withdraw via `withdraw`
- Removed Controller
  - Removed harvest from vault (only on strategy)
- Params added to track autocompounded rewards (lifeTimeEarned, lastHarvestedAt, lastHarvestAmount, assetsAtLastHarvest)
  this would work in sync with autoCompoundRatio to help us track harvests better.
- Fees
  - Strategy would report the autocompounded harvest amount to the vault
  - Calculation performanceFeeGovernance, performanceFeeStrategist, withdrawalFee, managementFee moved to the vault.
  - Vault mints shares for performanceFees and managementFee to the respective recipient (treasury, strategist)
  - withdrawal fees is transferred to the rewards address set
- Permission:
  - Strategist can now set performance, withdrawal and management fees
  - Governance will determine maxPerformanceFee, maxWithdrawalFee, maxManagementFee that can be set to prevent rug of funds.
- Strategy would take the actors from the vault it is connected to
- All goverance related fees goes to treasury

### Strategy

- No controller as middleman. The Strategy directly interacts with the vault
- withdrawToVault would withdraw all the funds from the strategy and move it into vault
- strategy would take the actors from the vault it is connected to
  - SettAccessControl removed
- fees calculation for autocompounding rewards moved to vault
- autoCompoundRatio param added to keep a track in which ratio harvested rewards are being autocompounded
- Strategy.withdrawAll to move all funds to the Vault
- Fees calculation moved to want for autocompounded part, strategy only calculates fees for reward part which is not autocompounded.

## Tests

If you're not familiar with brownie, see the [quickstart](https://eth-brownie.readthedocs.io/en/stable/quickstart.html).

Run tests:

```bash
brownie test -s --interactive
```

Run tests with coverage:

```bash
brownie test --coverage
```

A brief explanation of flags:

- `-s` - provides iterative display of the tests being executed
- `--coverage` - generates a test coverage report

## Formatting

Check linter rules for `*.json` and `*.sol` files:

```bash
yarn format:check
```

Fix linter errors for `*.json` and `*.sol` files:

```bash
yarn format
```

Check linter rules for `*.py` files:

```bash
black . --check
```

Fix linter errors for `*.py` files:

```bash
black .
```

## TODO:

- Add deposit hook on vault to warn the rewards contract.
