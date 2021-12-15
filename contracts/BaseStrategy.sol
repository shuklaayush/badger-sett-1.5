// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/proxy/Initializable.sol";

import "../interfaces/badger/IStrategy.sol";
import "../interfaces/badger/IVault.sol";

/*
    ===== Badger Base Strategy =====
    Common base class for all Sett strategies

    Changelog
    V1.1
    - Verify amount unrolled from strategy positions on withdraw() is within a threshold relative to the requested amount as a sanity check
    - Add version number which is displayed with baseStrategyVersion(). If a strategy does not implement this function, it can be assumed to be 1.0

    V1.2
    - Remove idle want handling from base withdraw() function. This should be handled as the strategy sees fit in _withdrawSome()

    V1.5
    - No controller as middleman. The Strategy directly interacts with the vault
    - withdrawToVault would withdraw all the funds from the strategy and move it into vault
    - strategy would take the actors from the vault it is connected to
        - SettAccessControl removed
    - fees calculation for autocompounding rewards moved to vault
    - autoCompoundRatio param added to keep a track in which ratio harvested rewards are being autocompounded
*/
abstract contract BaseStrategy is IStrategy, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    uint256 public constant MAX_BPS = 10_000; // MAX_BPS in terms of BPS = 100%

    address public want; // Token used for deposits
    address public vault; // address of the vault the strategy is connected to
    uint256 public withdrawalMaxDeviationThreshold; // max allowed slippage when withdrawing

    /// @notice percentage of rewards converted to want
    /// @dev converting of rewards to want during harvest should take place in this ratio
    /// @dev change this ratio if rewards are converted in a different percentage
    /// value ranges from 0 to 10_000
    /// 0: keeping 100% harvest in reward tokens
    /// 10_000: converting all rewards tokens to want token
    uint256 public autoCompoundRatio;

    // NOTE: You have to set autoCompoundRatio in the initializer of your strategy

    event SetWithdrawalMaxDeviationThreshold(uint256 nawMaxDeviationThreshold);

    /// @dev Initializer for the BaseStrategy
    /// @notice Make sure to call it from your specific Strategy
    function __BaseStrategy_init(address _vault) public initializer whenNotPaused {
        require(_vault != address(0), "Address 0");
        __Pausable_init();

        vault = _vault;

        withdrawalMaxDeviationThreshold = 50; // BPS
        // NOTE: See above
        autoCompoundRatio = 10_000;
    }

    // ===== Modifiers =====

    /// @dev For functions that only the governance should be able to call 
    /// @notice most of the time setting setters, or to rescue / sweep funds
    function _onlyGovernance() internal view {
        require(msg.sender == governance(), "onlyGovernance");
    }

    /// @dev For functions that only known bening entities should call
    function _onlyGovernanceOrStrategist() internal view {
        require(msg.sender == strategist() || msg.sender == governance(), "onlyGovernanceOrStrategist");
    }

    /// @dev For functions that only known bening entities should call
    function _onlyAuthorizedActors() internal view {
        require(msg.sender == keeper() || msg.sender == governance(), "onlyAuthorizedActors");
    }

    /// @dev For functions that only the vault should use
    function _onlyVault() internal view {
        require(msg.sender == vault, "onlyVault");
    }

    /// @dev Modifier used to check if the function is being called by a bening entity
    function _onlyAuthorizedActorsOrVault() internal view {
        require(msg.sender == keeper() || msg.sender == governance() || msg.sender == vault, "onlyAuthorizedActorsOrVault");
    }

    /// @dev Modifier used exclusively for pausing
    function _onlyAuthorizedPausers() internal view {
        require(msg.sender == guardian() || msg.sender == governance(), "onlyPausers");
    }

    /// ===== View Functions =====
    /// @dev Returns the version of the BaseStrategy 
    function baseStrategyVersion() external pure returns (string memory) {
        return "1.5";
    }

    /// @notice Get the balance of want held idle in the Strategy
    /// @notice public because used internally for accounting
    function balanceOfWant() public view override returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /// @notice Get the total balance of want realized in the strategy, whether idle or active in Strategy positions.
    function balanceOf() external view virtual override returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    /// @dev Returns the boolean that tells whether this strategy is supposed to be tended or not
    /// @notice This is basically a constant, the harvest bots checks if this is true and in that case will call `tend`
    function isTendable() external pure virtual returns (bool) {
        return false;
    }

    /// @dev Used to verify if a token can be transfered / sweeped (as it's not part of the strategy)
    function isProtectedToken(address token) public view returns (bool) {
        require(token != address(0), "Address 0");

        address[] memory protectedTokens = getProtectedTokens();
        for (uint256 i = 0; i < protectedTokens.length; i++) {
            if (token == protectedTokens[i]) {
                return true;
            }
        }
        return false;
    }

    /// @dev gets the governance
    function governance() public view returns (address) {
        return IVault(vault).governance();
    }

    /// @dev gets the strategist
    function strategist() public view returns (address) {
        return IVault(vault).strategist();
    }

    /// @dev gets the keeper
    function keeper() public view returns (address) {
        return IVault(vault).keeper();
    }

    /// @dev gets the guardian
    function guardian() public view returns (address) {
        return IVault(vault).guardian();
    }

    /// ===== Permissioned Actions: Governance =====
    
    /// @dev Allows to change withdrawalMaxDeviationThreshold
    /// @notice Anytime a withdrawal is done, the vault uses the current assets `vault.balance()` to calculate the value of each share
    /// @notice When the strategy calls `_withdraw` it uses this variable as a slippage check against the actual funds withdrawn
    function setWithdrawalMaxDeviationThreshold(uint256 _threshold) external {
        _onlyGovernance();
        require(_threshold <= MAX_BPS, "_threshold should be <= MAX_BPS");
        withdrawalMaxDeviationThreshold = _threshold;
        emit SetWithdrawalMaxDeviationThreshold(_threshold);
    }

    /// @dev Calls deposit, see below
    function earn() external override whenNotPaused {
        deposit();
    }

    /// @dev Causes the strategy to `_deposit` the idle want sitting in the strategy
    /// @notice Is basically the same as tend, except without custom code for it 
    function deposit() public virtual whenNotPaused {
        _onlyAuthorizedActorsOrVault();
        uint256 _amount = IERC20Upgradeable(want).balanceOf(address(this));
        if (_amount > 0) {
            _deposit(_amount);
        }
    }

    // ===== Permissioned Actions: Vault =====

    /// @notice Vault-only function to Withdraw partial funds, normally used with a vault withdrawal
    function withdrawToVault() external override whenNotPaused returns (uint256) {
        _onlyVault();

        _withdrawAll();

        balance = IERC20Upgradeable(want).balanceOf(address(this));
        _transferToVault(balance);

        return balance;
    }

    /// @notice Withdraw partial funds from the strategy, unrolling from strategy positions as necessary
    /// @dev If it fails to recover sufficient funds (defined by withdrawalMaxDeviationThreshold), the withdrawal should fail so that this unexpected behavior can be investigated
    function withdraw(uint256 _amount) external virtual override whenNotPaused {
        _onlyVault();
        require(_amount != 0, "Amount 0");

        // Withdraw from strategy positions, typically taking from any idle want first.
        _withdrawSome(_amount);
        uint256 _postWithdraw = IERC20Upgradeable(want).balanceOf(address(this));

        // Sanity check: Ensure we were able to retrieve sufficent want from strategy positions
        // If we end up with less than the amount requested, make sure it does not deviate beyond a maximum threshold
        if (_postWithdraw < _amount) {
            uint256 diff = _diff(_amount, _postWithdraw);

            // Require that difference between expected and actual values is less than the deviation threshold percentage
            require(diff <= _amount.mul(withdrawalMaxDeviationThreshold).div(MAX_BPS), "withdraw-exceed-max-deviation-threshold");
        }

        // Return the amount actually withdrawn if less than amount requested
        uint256 _toWithdraw = MathUpgradeable.min(_postWithdraw, _amount);

        // Transfer remaining to Vault to handle withdrawal
        _transferToVault(_toWithdraw);
    }

    // e.g. airdrop or donation
    // Discussion: https://discord.com/channels/785315893960900629/837083557557305375
    /// @dev The counterpart to _processExtraToken
    /// @dev Allows to emit the non protected tokens
    /// @notice this is for the tokens you didn't expect the strat to receive
    /// @notice instead of sweeping them, just emit so it saves time while offering security guarantees
    /// @notice This is not a rug vector as it can't use protected tokens
    /// @notice No address(0) check because _onlyNotProtectedTokens does it
    function emitNonProtectedToken(address _token) external override {
        _onlyVault();
        _onlyNotProtectedTokens(_token);
        IERC20Upgradeable(_token).safeTransfer(vault, IERC20Upgradeable(_token).balanceOf(address(this)));
        IVault(vault).reportAdditionalToken(_token);
    }

    /// @dev Withdraw the non protected token, used for sweeping it out
    /// @notice this is the version that just sends the assets to governance
    /// @notice No address(0) check because _onlyNotProtectedTokens does it
    function withdrawOther(address _asset) external override whenNotPaused {
        _onlyVault();
        _onlyNotProtectedTokens(_asset);
        IERC20Upgradeable(_asset).safeTransfer(vault, IERC20Upgradeable(_asset).balanceOf(address(this)));
    }

    /// ===== Permissioned Actions: Authoized Contract Pausers =====

    /// @dev Pause the contract
    /// @notice Check the `onlyWhenPaused` modifier for functionality that is blocked when pausing
    function pause() external {
        _onlyAuthorizedPausers();
        _pause();
    }

    /// @dev Unpause the contract
    /// @notice while a guardian can also pause, only governance (multisig with timelock) can unpause
    function unpause() external {
        _onlyGovernance();
        _unpause();
    }

    /// ===== Internal Helper Functions =====

    /// @dev function to transfer specific amount of want to vault from strategy
    /// @notice strategy should have idle funds >= _amount for this to happen
    /// @param _amount: the amount of want token to transfer to vault
    function _transferToVault(uint256 _amount) internal {
        if (_amount > 0) {
            IERC20Upgradeable(want).safeTransfer(vault, _amount);
        }
    }

    /// @dev function to report harvest to vault
    /// @param _harvestedAmount: amount of want token autocompounded during harvest
    function _reportToVault(
        uint256 _harvestedAmount
    ) internal whenNotPaused {
        IVault(vault).reportHarvest(_harvestedAmount);
    }

    /// @dev Report additional token income to the Vault, handles fees and sends directly to tree
    /// @notice This is how you emit tokens in V1.5
    /// @notice After calling this function, the tokens are gone, sent to fee receivers and badgerTree
    /// @notice This is a rug vector as it allows to move funds to the tree
    /// @notice for this reason I highly recommend you verify the tree is the badgerTree from the registry
    /// @notice also check for this to be used exclusively on harvest, exclusively on protectedTokens
    function _processExtraToken(address _token, uint256 _amount) internal {
        require(_token != want, "Not want, use _reportToVault");
        require(_token != address(0), "Address 0");
        require(_amount != 0, "Amount 0");

        IERC20Upgradeable(_token).safeTransfer(vault, _amount);
        IVault(vault).reportAdditionalToken(_token);
    }

    /// @notice Utility function to diff two numbers, expects higher value in first position
    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a >= b, "a should be >= b");
        return a.sub(b);
    }

    // ===== Abstract Functions: To be implemented by specific Strategies =====

    /// @dev Internal deposit logic to be implemented by Stratgies
    /// @param _want: the amount of want token to be deposited into the strategy
    function _deposit(uint256 _want) internal virtual;

    /// @notice Specify tokens used in yield process, should not be available to withdraw via withdrawOther()
    /// @param _asset: address of asset
    function _onlyNotProtectedTokens(address _asset) internal view {
        require(!isProtectedToken(_asset), "_onlyNotProtectedTokens");
    }

    /// @dev Gives the list of protected tokens
    /// @return array of protected tokens
    function getProtectedTokens() public view virtual returns (address[] memory);

    /// @dev Internal logic for strategy migration. Should exit positions as efficiently as possible
    function _withdrawAll() internal virtual;

    /// @dev Internal logic for partial withdrawals. Should exit positions as efficiently as possible.
    /// @dev The withdraw() function shell automatically uses idle want in the strategy before attempting to withdraw more using this
    /// @param _amount: the amount of want token to be withdrawm from the strategy
    /// @return withdrawn amount from the strategy
    function _withdrawSome(uint256 _amount) internal virtual returns (uint256);

    /// @dev Realize returns from positions
    /// @dev Returns can be reinvested into positions, or distributed in another fashion
    /// @return harvested : total amount harvested
    function harvest() external virtual override returns (TokenAmount[] memory harvested);

    function tend() external virtual override returns (TokenAmount[] memory tended);

    /// @dev User-friendly name for this strategy for purposes of convenient reading
    /// @return Name of the strategy
    function getName() external pure virtual returns (string memory);

    /// @dev Balance of want currently held in strategy positions
    /// @return balance of want held in strategy positions
    function balanceOfPool() public view virtual override returns (uint256);

    /// @dev Calculate the total amount of rewards accured.
    /// @notice if there are multiple reward tokens this function should take all of them into account
    /// @return rewards - the TokenAmount of rewards accured
    function balanceOfRewards() external view virtual override returns (TokenAmount[] memory rewards);

    uint256[49] private __gap;
}
