// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/proxy/Initializable.sol";

import "./lib/SettAccessControl.sol";

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

    uint256 public constant MAX = 10_000; // MAX in terms of BPS = 100%


    address public want; // Token used for deposits
    address public vault; // address of the vault the strategy is connected to
    uint256 public withdrawalMaxDeviationThreshold; // max allowed slippage when withdrawing

    /// @notice percentage of rewards converted to want
    /// @dev converting of rewards to want during harvest should take place in this ratio
    /// @dev change this ratio if rewards are converted in a different percentage
    /// value ranges from 0 to 10_000
    /// 0: keeping 100% harvest in reward tokens
    /// 10_000: converting all rewards tokens to want token
    uint256 public autoCompoundRatio = 10_000; // NOTE: Since this is upgradeable this won't be set

    function __BaseStrategy_init(address _vault) public initializer whenNotPaused {
        __Pausable_init();

        vault = _vault;

        withdrawalMaxDeviationThreshold = 50;
    }

    // ===== Modifiers =====

    function _onlyGovernance() internal view {
        require(msg.sender == governance(), "onlyGovernance");
    }

    function _onlyGovernanceOrStrategist() internal view {
        require(msg.sender == strategist() || msg.sender == governance(), "onlyGovernanceOrStrategist");
    }

    function _onlyAuthorizedActors() internal view {
        require(msg.sender == keeper() || msg.sender == governance(), "onlyAuthorizedActors");
    }

    function _onlyVault() internal view {
        require(msg.sender == vault, "onlyVault");
    }

    function _onlyAuthorizedActorsOrVault() internal view {
        require(msg.sender == keeper() || msg.sender == governance() || msg.sender == vault, "onlyAuthorizedActorsOrVault");
    }

    function _onlyAuthorizedPausers() internal view {
        require(msg.sender == guardian() || msg.sender == governance(), "onlyPausers");
    }

    /// ===== View Functions =====
    function baseStrategyVersion() public view returns (string memory) {
        return "1.5";
    }

    /// @notice Get the balance of want held idle in the Strategy
    function balanceOfWant() public view override returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /// @notice Get the total balance of want realized in the strategy, whether idle or active in Strategy positions.
    function balanceOf() public view virtual override returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    function isTendable() public view virtual returns (bool) {
        return false;
    }

    function isProtectedToken(address token) public view returns (bool) {
        address[] memory protectedTokens = getProtectedTokens();
        for (uint256 i = 0; i < protectedTokens.length; i++) {
            if (token == protectedTokens[i]) {
                return true;
            }
        }
        return false;
    }

    function governance() public view returns (address) {
        return IVault(vault).governance();
    }

    function strategist() public view returns (address) {
        return IVault(vault).strategist();
    }

    function keeper() public view returns (address) {
        return IVault(vault).keeper();
    }

    function guardian() public view returns (address) {
        return IVault(vault).guardian();
    }

    /// ===== Permissioned Actions: Governance =====

    function setVault(address _vault) external {
        // I think we'll remove this
        // Make strat unable to change vault so that it can't be used to swap / rug
        _onlyGovernance();
        vault = _vault;
    }

    function setWithdrawalMaxDeviationThreshold(uint256 _threshold) external {
        _onlyGovernance();
        require(_threshold <= MAX, "base-strategy/excessive-max-deviation-threshold");
        withdrawalMaxDeviationThreshold = _threshold;
    }

    function earn() public override whenNotPaused {
        deposit();
    }

    function deposit() public virtual whenNotPaused {
        _onlyAuthorizedActorsOrVault();
        uint256 _want = IERC20Upgradeable(want).balanceOf(address(this));
        if (_want > 0) {
            _deposit(_want);
        }
        _postDeposit();
    }

    // ===== Permissioned Actions: Vault =====

    /// @notice Vault-only function to Withdraw partial funds, normally used with a vault withdrawal
    function withdrawToVault() external override whenNotPaused returns (uint256 balance) {
        _onlyVault();

        _withdrawAll();

        _transferToVault(IERC20Upgradeable(want).balanceOf(address(this)));
    }

    /// @notice Withdraw partial funds from the strategy, unrolling from strategy positions as necessary
    /// @dev If it fails to recover sufficient funds (defined by withdrawalMaxDeviationThreshold), the withdrawal should fail so that this unexpected behavior can be investigated
    function withdraw(uint256 _amount) external virtual override whenNotPaused {
        _onlyVault();

        // Withdraw from strategy positions, typically taking from any idle want first.
        _withdrawSome(_amount);
        uint256 _postWithdraw = IERC20Upgradeable(want).balanceOf(address(this));

        // Sanity check: Ensure we were able to retrieve sufficent want from strategy positions
        // If we end up with less than the amount requested, make sure it does not deviate beyond a maximum threshold
        if (_postWithdraw < _amount) {
            uint256 diff = _diff(_amount, _postWithdraw);

            // Require that difference between expected and actual values is less than the deviation threshold percentage
            require(diff <= _amount.mul(withdrawalMaxDeviationThreshold).div(MAX), "base-strategy/withdraw-exceed-max-deviation-threshold");
        }

        // Return the amount actually withdrawn if less than amount requested
        uint256 _toWithdraw = MathUpgradeable.min(_postWithdraw, _amount);

        // Transfer remaining to Vault to handle withdrawal
        _transferToVault(_toWithdraw);
    }

    // NOTE: must exclude any tokens used in the yield
    // Vault role - withdraw should return to Vault
    /// @return balance - balance of asset withdrawn
    function withdrawOther(address _asset) external override whenNotPaused returns (uint256 balance) {
        _onlyVault();
        _onlyNotProtectedTokens(_asset);

        balance = IERC20Upgradeable(_asset).balanceOf(address(this));
        IERC20Upgradeable(_asset).safeTransfer(vault, balance);
        return balance;
    }

    /// ===== Permissioned Actions: Authoized Contract Pausers =====

    function pause() external {
        _onlyAuthorizedPausers();
        _pause();
    }

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
    /// @param _harvestTime: timestamp of harvest
    /// @param _assetsAtLastHarvest: assets in pool for which the harvest took place.
    function _reportToVault(
        uint256 _harvestedAmount,
        uint256 _harvestTime,
        uint256 _assetsAtLastHarvest
    ) internal whenNotPaused {
        IVault(vault).report(_harvestedAmount, _harvestTime, _assetsAtLastHarvest);
    }

    /// @dev used to manage the governance and strategist fee on earned rewards , make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token) internal {
        IVault(vault).reportAdditionalToken(_amount, _token);
    }

    /// @notice Utility function to diff two numbers, expects higher value in first position
    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a >= b, "diff/expected-higher-number-in-first-position");
        return a.sub(b);
    }

    // function setAutoCompoundRatio(uint256 _ratio) internal {
    //     require(_ratio <= MAX, "base-strategy/excessive-auto-compound-ratio");
    //     autoCompoundRatio = _ratio;
    // }

    // ===== Abstract Functions: To be implemented by specific Strategies =====

    /// @dev Internal deposit logic to be implemented by Stratgies
    /// @param _want: the amount of want token to be deposited into the strategy
    function _deposit(uint256 _want) internal virtual;

    function _postDeposit() internal virtual {
        //no-op by default
    }

    /// @notice Specify tokens used in yield process, should not be available to withdraw via withdrawOther()
    /// @param _asset: address of asset
    function _onlyNotProtectedTokens(address _asset) internal {
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
    function harvest() external virtual returns (uint256 harvested);

    /// @dev User-friendly name for this strategy for purposes of convenient reading
    /// @return Name of the strategy
    function getName() external pure virtual returns (string memory);

    /// @dev Balance of want currently held in strategy positions
    /// @return balance of want held in strategy positions
    function balanceOfPool() public view virtual override returns (uint256);

    /// @dev Calculate the total amount of rewards accured.
    /// @notice if there are multiple reward tokens this function should take all of them into account
    /// @return the amount of rewards accured
    function balanceOfRewards() public view virtual override returns (uint256);

    uint256[49] private __gap;
}
