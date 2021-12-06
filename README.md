# Badger Vaults 1.5 - WARNING - CODE NOT AUDITED

A linear improvement from original architecture. No longer using Controller, just Vault and Strategy.



# Badger Vaults 1.5

A simplified architecture for Vaults, that uses exclusively:
Vault -> Handle Deposits, accounting and emission of events
Strategy -> Uses funds to generate yield on them

With additional extension from the original Badger Sett Fork:
- Contracts are upgradeable
- All contracts Pausable
- Deposits can be paused separately
- Handling cases of Strategy that only emits funds

With additional new feature:
- Performance Fees, issued as shares
- Management and Withdrawal fees, also issued as shares
- Ability to emit to the badger tree directly
- Remove the controller
- Settings are in the vaults, and the strategy has simpler / leaner bytecode


# Additional Docs
See the User Stories:
https://mint-salesman-909.notion.site/Badger-Vaults-1-5-User-Stories-2eae32b1eebc4892a6188f6aa9b17e5a

See the Overview:
https://mint-salesman-909.notion.site/Badger-Vaults-1-5-Overview-ab9c64a076af4ba3913d1430c01d8f6e


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



# Breaking Changes

List of changes for Vaults 1.5 that make it breaking for some scripts

## No more Controller
That's the point

## setRewards is gone
Replace by setTreasury

## Vault handles report of funds

## badgerTree is in the Vault
Set in the vault and transfered when reported by the strat

## Harvest and Tend return a list of tokens
The list is to be interpreted as the `protectedTokens` and the actual enforcing has to be done by the Strategist



## SECURITY!!! IMPORTANT

It it extremely important that governance is a timelock, as some changes (changing strategies) can be used with malicious intent

DO NOT trust these contracts, unless `governance` is a timelock with a delay of over a day (typically 2 days)
