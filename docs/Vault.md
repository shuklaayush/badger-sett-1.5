## `Vault`






### `initialize(address _token, address _governance, address _keeper, address _guardian, address _treasury, address _strategist, address _badgerTree, string _name, string _symbol, uint256[4] _feeConfig)` (public)

Initializes the Sett. Can only be called once, ideally when the contract is deployed.




### `_onlyAuthorizedPausers()` (internal)

Checks whether a call is from guardian or governance.



### `_onlyStrategy()` (internal)

Checks whether a call is from the strategy.



### `version() → string` (external)

Used to track the deployed version of the contract.




### `getPricePerFullShare() → uint256` (public)

Gives the price for a single Sett share.


Sett starts with a price per share of 1.


### `balance() → uint256` (public)

Gives the total balance of the underlying token within the sett and strategy system.




### `available() → uint256` (public)

Defines how much of the Setts' underlying is available for strategy to borrow.




### `deposit(uint256 _amount)` (external)

Deposits `_amount` tokens, issuing shares. 
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositFor` for details on how deposit is implemented. 


### `deposit(uint256 _amount, bytes32[] proof)` (external)

Deposits `_amount` tokens, issuing shares. 
        Checks the guestlist to verify that the calling account is authorized to make a deposit for the specified `_amount`.
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositForWithAuthorization` for details on guestlist authorization.


### `depositAll()` (external)

Deposits all tokens, issuing shares. 
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositFor` for details on how deposit is implemented.

### `depositAll(bytes32[] proof)` (external)

Deposits all tokens, issuing shares. 
        Checks the guestlist to verify that the calling is authorized to make a full deposit.
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositForWithAuthorization` for details on guestlist authorization.


### `depositFor(address _recipient, uint256 _amount)` (external)

Deposits `_amount` tokens, issuing shares to `recipient`. 
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositFor` for details on how deposit is implemented. 


### `depositFor(address _recipient, uint256 _amount, bytes32[] proof)` (external)

Deposits `_amount` tokens, issuing shares to `recipient`. 
        Checks the guestlist to verify that `recipient` is authorized to make a deposit for the specified `_amount`.
        Note that deposits are not accepted when the Sett is paused or when `pausedDeposit` is true. 


See `_depositForWithAuthorization` for details on guestlist authorization.


### `withdraw(uint256 _shares)` (external)

Redeems `_shares` for an appropriate amount of tokens.
        Note that withdrawals are not processed when the Sett is paused. 


See `_withdraw` for details on how withdrawals are processed.


### `withdrawAll()` (external)

Redeems all shares, issuing an appropriate amount of tokens. 
        Note that withdrawals are not processed when the Sett is paused. 


See `_withdraw` for details on how withdrawals are processed.

### `reportHarvest(uint256 _harvestedAmount)` (external)

Used by the strategy to report a harvest to the sett.
        Issues shares for the strategist and treasury based on the performance fees and harvested amount. 
        Issues shares for the treasury based on the management fee and the time elapsed since last harvest. 
        Updates harvest variables for on-chain APR tracking.
        This can only be called by the strategy.


This implicitly trusts that the strategy reports the correct amount.
     Pausing on this function happens at the strategy level.


### `reportAdditionalToken(address _token)` (external)

Used by the strategy to report harvest of additional tokens to the sett.
        Charges performance fees on the additional tokens and transfers fees to treasury and strategist. 
        The remaining amount is sent to badgerTree for emissions.
        Updates harvest variables for on-chain APR tracking.
        This can only be called by the strategy.


This function is called after the strategy sends the additional tokens to the sett.
     Pausing on this function happens at the strategy level.


### `setTreasury(address _treasury)` (external)

Changes the treasury address.
        Treasury is recipient of management and governance performance fees.
        This can only be called by governance.
        Note that this can only be called when sett is not paused.




### `setStrategy(address _strategy)` (external)

Changes the strategy address.
        This can only be called by governance.
        Note that this can only be called when sett is not paused.


This is a rug vector, pay extremely close attention to the next strategy being set.
     Changing the strategy should happen only via timelock.
     This function must not be callable when the sett is paused as this would force depositors into a strategy they may not want to use.


### `setMaxWithdrawalFee(uint256 _fees)` (external)

Sets the max withdrawal fee that can be charged by the Sett.
        This can only be called by governance.


The input `_fees` should be less than the `WITHDRAWAL_FEE_HARD_CAP` hard-cap.


### `setMaxPerformanceFee(uint256 _fees)` (external)

Sets the max performance fee that can be charged by the Sett.
        This can only be called by governance.


The input `_fees` should be less than the `PERFORMANCE_FEE_HARD_CAP` hard-cap.


### `setMaxManagementFee(uint256 _fees)` (external)

Sets the max management fee that can be charged by the Sett.
        This can only be called by governance.


The input `_fees` should be less than the `MANAGEMENT_FEE_HARD_CAP` hard-cap.


### `setGuardian(address _guardian)` (external)

Changes the guardian address.
        Guardian is an authorized actor that can pause the sett in case of an emergency.
        This can only be called by governance.




### `setToEarnBps(uint256 _newToEarnBps)` (external)

Sets the fraction of sett balance (in basis points) that the strategy can borrow.
        This can be called by either governance or strategist.
        Note that this can only be called when the sett is not paused.




### `setGuestList(address _guestList)` (external)

Changes the guestlist address.
        The guestList is used to gate or limit deposits. If no guestlist is set then anyone can deposit any amount.
        This can be called by either governance or strategist.
        Note that this can only be called when the sett is not paused.




### `setWithdrawalFee(uint256 _withdrawalFee)` (external)

Sets the withdrawal fee charged by the Sett.
        The fee is taken at the time of withdrawals in the underlying token which is then used to issue new shares for the treasury.
        The new withdrawal fee should be less than `maxWithdrawalFee`.
        This can be called by either governance or strategist.


See `_withdraw` to see how withdrawal fee is charged.


### `setPerformanceFeeStrategist(uint256 _performanceFeeStrategist)` (external)

Sets the performance fee taken by the strategist on the harvests.
        The fee is taken at the time of harvest reporting for both the underlying token and additional tokens.
        For the underlying token, the fee is used to issue new shares for the strategist.
        The new performance fee should be less than `maxPerformanceFee`.
        This can be called by either governance or strategist.


See `reportHarvest` and `reportAdditionalToken` to see how performance fees are charged.


### `setPerformanceFeeGovernance(uint256 _performanceFeeGovernance)` (external)

Sets the performance fee taken by the treasury on the harvests.
        The fee is taken at the time of harvest reporting for both the underlying token and additional tokens.
        For the underlying token, the fee is used to issue new shares for the treasury.
        The new performance fee should be less than `maxPerformanceFee`.
        This can be called by either governance or strategist.


See `reportHarvest` and `reportAdditionalToken` to see how performance fees are charged.


### `setManagementFee(uint256 _fees)` (external)

Sets the management fee taken by the treasury on the AUM in the sett.
        The fee is calculated at the time of `reportHarvest` and is used to issue new shares for the treasury.
        The new management fee should be less than `maxManagementFee`.
        This can be called by either governance or strategist.


See `_handleFees` to see how the management fee is calculated.


### `withdrawToVault()` (external)

Withdraws all funds from the strategy back to the sett.
        This can be called by either governance or strategist.


This calls `_withdrawAll` on the strategy and transfers the balance to the sett.

### `emitNonProtectedToken(address _token)` (external)

Sends balance of any extra token earned by the strategy (from airdrops, donations etc.) 
        to the badgerTree for emissions.
        The `_token` should be different from any tokens managed by the strategy.
        This can only be called by either strategist or governance.


See `BaseStrategy.emitNonProtectedToken` for details.


### `sweepExtraToken(address _token)` (external)

Sweeps the balance of an extra token from the vault and strategy and sends it to governance.
        The `_token` should be different from any tokens managed by the strategy.
        This can only be called by either strategist or governance.


Sweeping doesn't take any fee.


### `earn()` (external)

Deposits the available balance of the underlying token into the strategy.
        The strategy then uses the amount for yield-generating activities.
        This can be called by either the keeper or governance.
        Note that earn cannot be called when deposits are paused.


Pause is enforced at the Strategy level (this allows to still earn yield when the Vault is paused)

### `pauseDeposits()` (external)

Pauses only deposits.
        This can be called by either guardian or governance.



### `unpauseDeposits()` (external)

Unpauses deposits.
        This can only be called by governance.



### `pause()` (external)

Pauses everything.
        This can be called by either guardian or governance.



### `unpause()` (external)

Unpauses everything
        This can only be called by governance.



### `_depositFor(address _recipient, uint256 _amount)` (internal)

Deposits `_amount` tokens, issuing shares to `recipient`. 
        Note that deposits are not accepted when `pausedDeposit` is true. 


This is the actual deposit operation.
     Deposits are based on the realized value of underlying assets between Sett & associated Strategy


### `_depositWithAuthorization(uint256 _amount, bytes32[] proof)` (internal)



See `_depositWithAuthorization`

### `_depositForWithAuthorization(address _recipient, uint256 _amount, bytes32[] proof)` (internal)



Verifies that `_recipient` is authorized to deposit `_amount` based on the guestlist.
     See `_depositFor` for deposit details.

### `_withdraw(uint256 _shares)` (internal)

Redeems `_shares` for an appropriate amount of tokens.


This is the actual withdraw operation.
     Withdraws from strategy positions if sett doesn't contain enough tokens to process the withdrawal. 
     Calculates withdrawal fees and issues corresponding shares to treasury.
     No rebalance implementation for lower fees and faster swaps


### `_calculateFee(uint256 amount, uint256 feeBps) → uint256` (internal)



Helper function to calculate fees.


### `_calculatePerformanceFee(uint256 _amount) → uint256, uint256` (internal)



Helper function to calculate governance and strategist performance fees. Make sure to use it to get paid!


### `_mintSharesFor(address recipient, uint256 _amount, uint256 _pool)` (internal)



Helper function to issue shares to `recipient` based on an input `_amount` and `_pool` size.


### `_handleFees(uint256 _harvestedAmount, uint256 harvestTime)` (internal)



Helper function that issues shares based on performance and management fee when a harvest is reported.



### `TreeDistribution(address token, uint256 amount, uint256 blockNumber, uint256 timestamp)`

===== Events ====



### `Harvested(address token, uint256 amount, uint256 blockNumber, uint256 timestamp)`





### `SetTreasury(address newTreasury)`





### `SetStrategy(address newStrategy)`





### `SetToEarnBps(uint256 newEarnToBps)`





### `SetMaxWithdrawalFee(uint256 newMaxWithdrawalFee)`





### `SetMaxPerformanceFee(uint256 newMaxPerformanceFee)`





### `SetMaxManagementFee(uint256 newMaxManagementFee)`





### `SetGuardian(address newGuardian)`





### `SetGuestList(address newGuestList)`





### `SetWithdrawalFee(uint256 newWithdrawalFee)`





### `SetPerformanceFeeStrategist(uint256 newPerformanceFeeStrategist)`





### `SetPerformanceFeeGovernance(uint256 newPerformanceFeeGovernance)`





### `SetManagementFee(uint256 newManagementFee)`





### `PauseDeposits(address pausedBy)`





### `UnpauseDeposits(address pausedBy)`







