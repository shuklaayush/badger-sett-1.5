## `BaseStrategy`

### `__BaseStrategy_init(address _vault)` (public)

Initializes BaseStrategy. Can only be called once.
Make sure to call it from the initializer of the derived strategy.

### `_onlyGovernance()` (internal)

Checks whether a call is from governance.

For functions that only the governance should be able to call
Most of the time setting setters, or to rescue/sweep funds

### `_onlyGovernanceOrStrategist()` (internal)

Checks whether a call is from strategist or governance.

For functions that only known benign entities should call

### `_onlyAuthorizedActors()` (internal)

Checks whether a call is from keeper or governance.

For functions that only known benign entities should call

### `_onlyVault()` (internal)

Checks whether a call is from the vault.

For functions that only the vault should use

### `_onlyAuthorizedActorsOrVault()` (internal)

Checks whether a call is from keeper, governance or the vault.

Modifier used to check if the function is being called by a benign entity

### `_onlyAuthorizedPausers()` (internal)

Checks whether a call is from guardian or governance.

Modifier used exclusively for pausing

### `baseStrategyVersion() → string` (external)

===== View Functions =====
Used to track the deployed version of BaseStrategy.

### `balanceOfWant() → uint256` (public)

Gives the balance of want held idle in the Strategy.

Public because used internally for accounting

### `balanceOf() → uint256` (external)

Gives the total balance of want managed by the strategy.
This includes all want deposited to active strategy positions as well as any idle want in the strategy.

### `isTendable() → bool` (external)

Tells whether the strategy is supposed to be tended.

This is usually a constant. The harvest keeper would only call `tend` if this is true.

### `_isTendable() → bool` (internal)

### `isProtectedToken(address token) → bool` (public)

Checks whether a token is a protected token.
Protected tokens are managed by the strategy and can't be transferred/sweeped.

### `governance() → address` (public)

Fetches the governance address from the vault.

### `strategist() → address` (public)

Fetches the strategist address from the vault.

### `keeper() → address` (public)

Fetches the keeper address from the vault.

### `guardian() → address` (public)

Fetches the guardian address from the vault.

### `setWithdrawalMaxDeviationThreshold(uint256 _threshold)` (external)

Sets the max withdrawal deviation (percentage loss) that is acceptable to the strategy.
This can only be called by governance.

This is used as a slippage check against the actual funds withdrawn from strategy positions.
See `withdraw`.

### `earn()` (external)

Deposits any idle want in the strategy into positions.
This can be called by either the vault, keeper or governance.
Note that deposits don't work when the strategy is paused.

See `deposit`.

### `deposit()` (public)

Deposits any idle want in the strategy into positions.
This can be called by either the vault, keeper or governance.
Note that deposits don't work when the strategy is paused.

Is basically the same as tend, except without custom code for it

### `withdrawToVault() → uint256 balance` (external)

Withdraw all funds from the strategy to the vault, unrolling all positions.
This can only be called by the vault.

This can be called even when paused, and strategist can trigger this via the vault.
The idea is that this can allow recovery of funds back to the strategy faster.
The risk is that if \_withdrawAll causes a loss, this can be triggered.
However the loss could only be triggered once (just like if governance called)
as pausing the strats would prevent earning again.

### `withdraw(uint256 _amount)` (external)

Withdraw partial funds from the strategy to the vault, unrolling from strategy positions as necessary.
This can only be called by the vault.
Note that withdraws don't work when the strategy is paused.

If the strategy fails to recover sufficient funds (defined by `withdrawalMaxDeviationThreshold`),
the withdrawal would fail so that this unexpected behavior can be investigated.

### `emitNonProtectedToken(address _token)` (external)

Sends balance of any extra token earned by the strategy (from airdrops, donations etc.) to the vault.
The `_token` should be different from any tokens managed by the strategy.
This can only be called by the vault.

This is a counterpart to `_processExtraToken`.
This is for tokens that the strategy didn't expect to receive. Instead of sweeping, we can directly
emit them via the badgerTree. This saves time while offering security guarantees.
No address(0) check because \_onlyNotProtectedTokens does it.
This is not a rug vector as it can't use protected tokens.

### `withdrawOther(address _asset)` (external)

Withdraw the balance of a non-protected token to the vault.
This can only be called by the vault.

Should only be used in an emergency to sweep any asset.
This is the version that sends the assets to governance.
No address(0) check because \_onlyNotProtectedTokens does it.

### `pause()` (external)

Pauses the strategy.
This can be called by either guardian or governance.

Check the `onlyWhenPaused` modifier for functionality that is blocked when pausing

### `unpause()` (external)

Unpauses the strategy.
This can only be called by governance (usually a multisig behind a timelock).

### `_transferToVault(uint256 _amount)` (internal)

Transfers `_amount` of want to the vault.

Strategy should have idle funds >= `_amount`.

### `_reportToVault(uint256 _harvestedAmount)` (internal)

Report an harvest to the vault.

### `_processExtraToken(address _token, uint256 _amount)` (internal)

Sends balance of an additional token (eg. reward token) earned by the strategy to the vault.
This should usually be called exclusively on protectedTokens.
Calls `Vault.reportAdditionalToken` to process fees and forward amount to badgerTree to be emitted.

This is how you emit tokens in V1.5
After calling this function, the tokens are gone, sent to fee receivers and badgerTree
This is a rug vector as it allows to move funds to the tree
For this reason, it is recommended to verify the tree is the badgerTree from the registry
and also check for this to be used exclusively on harvest, exclusively on protectedTokens.

### `_diff(uint256 a, uint256 b) → uint256` (internal)

Utility function to diff two numbers, expects higher value in first position

### `_deposit(uint256 _want)` (internal)

Internal deposit logic to be implemented by a derived strategy.

### `_onlyNotProtectedTokens(address _asset)` (internal)

Checks if a token is not used in yield process.

### `getProtectedTokens() → address[]` (public)

Gives the list of protected tokens.

### `_withdrawAll()` (internal)

Internal logic for strategy migration. Should exit positions as efficiently as possible.

### `_withdrawSome(uint256 _amount) → uint256` (internal)

Internal logic for partial withdrawals. Should exit positions as efficiently as possible.
Should ideally use idle want in the strategy before attempting to exit strategy positions.

### `harvest() → struct BaseStrategy.TokenAmount[] harvested` (external)

Realize returns from strategy positions.
This can only be called by keeper or governance.
Note that harvests don't work when the strategy is paused.

Returns can be reinvested into positions, or distributed in another fashion.

### `_harvest() → struct BaseStrategy.TokenAmount[] harvested` (internal)

Virtual function that should be overridden with the logic for harvest.
Should report any want or non-want gains to the vault.
Also see `harvest`.

### `tend() → struct BaseStrategy.TokenAmount[] tended` (external)

Tend strategy positions as needed to maximize returns.
This can only be called by keeper or governance.
Note that tend doesn't work when the strategy is paused.

Is only called by the keeper when `isTendable` is true.

### `_tend() → struct BaseStrategy.TokenAmount[] tended` (internal)

Virtual function that should be overridden with the logic for tending.
Also see `tend`.

### `getName() → string` (external)

Fetches the name of the strategy.

Should be user-friendly and easy to read.

### `balanceOfPool() → uint256` (public)

Gives the balance of want held in strategy positions.

### `balanceOfRewards() → struct BaseStrategy.TokenAmount[] rewards` (external)

Gives the total amount of pending rewards accrued for each token.

Should take into account all reward tokens.

### `SetWithdrawalMaxDeviationThreshold(uint256 newMaxDeviationThreshold)`

### `TokenAmount`

address token

uint256 amount
