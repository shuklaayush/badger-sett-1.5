// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./lib/SettAccessControl.sol";

import {IVault} from "interfaces/badger/IVault.sol";
import {IStrategy} from "interfaces/badger/IStrategy.sol";
import {IERC20Detailed} from "interfaces/erc20/IERC20Detailed.sol";
import {BadgerGuestListAPI} from "interfaces/yearn/BadgerGuestlistApi.sol";


/*
    Source: https://github.com/iearn-finance/yearn-protocol/blob/develop/contracts/vaults/yVault.sol
    
    Changelog:

    V1.1
    * Strategist no longer has special function calling permissions
    * Version function added to contract
    * All write functions, with the exception of transfer, are pausable
    * Keeper or governance can pause
    * Only governance can unpause

    V1.2
    * Transfer functions are now pausable along with all other non-permissioned write functions
    * All permissioned write functions, with the exception of pause() & unpause(), are pausable as well

    V1.3
    * Add guest list functionality
    * All deposits can be optionally gated by external guestList approval logic on set guestList contract

    V1.4
    * Add depositFor() to deposit on the half of other users. That user will then be blockLocked.

    V1.5
    * Removed Controller
        - Removed harvest from vault (only on strategy)
    * Params added to track autocompounded rewards (lifeTimeEarned, lastHarvestedAt, lastHarvestAmount, assetsAtLastHarvest)
      this would work in sync with autoCompoundRatio to help us track harvests better.
    * Fees
        - Strategy would report the autocompounded harvest amount to the vault
        - Calculation performanceFeeGovernance, performanceFeeStrategist, withdrawalFee, managementFee moved to the vault.
        - Vault mints shares for performanceFees and managementFee to the respective recipient
        - withdrawal fees is transferred to the rewards address set 
    * Permission:
        - Strategist can now set performance and withdrawl fees
        - Governance will determine maxPerformanceFee and maxWithdrawalFee that can be set to prevent rug of rewards from strategist.
    * Strategy would take the actors from the vault it is connected to
*/

contract Vault is ERC20Upgradeable, SettAccessControl, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public token; // Token used for deposits
    BadgerGuestListAPI public guestList; // guestlist when vault is in experiment/ guarded state

    address public strategy; // address of the strategy connected to the vault
    address public guardian; // guardian of vault and strategy 
    address public rewards; // address of rewards contract

    /// @dev name and symbol prefixes for lpcomponent token of vault
    string internal constant _defaultNamePrefix = "Badger Sett ";
    string internal constant _symbolSymbolPrefix = "b";

    /// Params to track autocompounded rewards 
    uint256 public lifeTimeEarned; // keeps track of total earnings
    uint256 public lastHarvestedAt; // timestamp of the last harvest
    uint256 public lastHarvestAmount; // amount harvested during last harvest
    uint256 public assetsAtLastHarvest; // assets for which the harvest took place.

    /// Fees ///
    /// @notice all fees will be in bps
    
    uint256 public performanceFeeGovernance;
    uint256 public performanceFeeStrategist;
    uint256 public withdrawalFee;
    uint256 public managementFee;

    uint256 public maxPerformanceFee; // maximum allowed performance fees
    uint256 public maxWithdrawalFee; // maximum allowed withdrawal fees

    uint256 public min; // NOTE: in BPS, minimum amount of token to deposit into strategy when earn is called

    // Constants
    uint256 public constant MAX = 10_000;
    uint256 public constant SECS_PER_YEAR  = 31_556_952;  // 365.2425 days

    event FullPricePerShareUpdated(uint256 value, uint256 indexed timestamp, uint256 indexed blockNumber);

    function initialize(
        address _token,
        address _governance,
        address _keeper,
        address _guardian,
        address _strategist,
        bool _overrideTokenName,
        string memory _namePrefix,
        string memory _symbolPrefix,
        uint256[4] memory _feeConfig
    ) public initializer whenNotPaused {

        require(_token != address(0)); // dev: _token address should not be zero

        IERC20Detailed namedToken = IERC20Detailed(_token);
        string memory tokenName = namedToken.name();
        string memory tokenSymbol = namedToken.symbol();

        string memory name;
        string memory symbol;

        if (_overrideTokenName) {
            name = string(abi.encodePacked(_namePrefix, tokenName));
            symbol = string(abi.encodePacked(_symbolPrefix, tokenSymbol));
        } else {
            name = string(abi.encodePacked(_defaultNamePrefix, tokenName));
            symbol = string(abi.encodePacked(_symbolSymbolPrefix, tokenSymbol));
        }

        // Initializing the lpcomponent token
        __ERC20_init(name, symbol);

        token = IERC20Upgradeable(_token);
        governance = _governance;
        rewards = _governance;
        strategist = _strategist;
        keeper = _keeper;
        guardian = _guardian;

        lastHarvestedAt = block.timestamp; // setting initial value to the time when the vault was deployed

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];
        managementFee = _feeConfig[3];
        maxPerformanceFee = 5_000; // 50% maximum performance fee
        maxWithdrawalFee = 100; // 1% maximum withdrawal fee

        min = 10_000; // initial value of min 

        emit FullPricePerShareUpdated(getPricePerFullShare(), now, block.number);
    }

    /// ===== Modifiers ====


    function _onlyAuthorizedPausers() internal view {
        require(msg.sender == guardian || msg.sender == governance, "onlyPausers");
    }

    /// ===== View Functions =====

    function version() public view returns (string memory) {
        return "1.5";
    }

    function getPricePerFullShare() public virtual view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return balance().mul(1e18).div(totalSupply());
    }

    /// @notice Return the total balance of the underlying token within the system
    /// @notice Sums the balance in the Sett and the Strategy
    function balance() public virtual view returns (uint256) {
        return token.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    /// @notice Defines how much of the Setts' underlying can be borrowed by the Strategy for use
    /// @notice Custom logic in here for how much the vault allows to be borrowed
    /// @notice Sets minimum required on-hand to keep small withdrawals cheap
    function available() public virtual view returns (uint256) {
        return token.balanceOf(address(this)).mul(min).div(MAX);
    }

    /// ===== Public Actions =====

    /// @notice Deposit assets into the Sett, and return corresponding shares to the user
    function deposit(uint256 _amount) public whenNotPaused {
        _depositWithAuthorization(_amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function deposit(uint256 _amount, bytes32[] memory proof) public whenNotPaused {
        _depositWithAuthorization(_amount, proof);
    }

    /// @notice Convenience function: Deposit entire balance of asset into the Sett, and return corresponding shares to the user
    function depositAll() external whenNotPaused {
        _depositWithAuthorization(token.balanceOf(msg.sender), new bytes32[](0));
    }

    /// @notice DepositAll variant with proof for merkle guest list
    function depositAll(bytes32[] memory proof) external whenNotPaused {
        _depositWithAuthorization(token.balanceOf(msg.sender), proof);
    }

    /// @notice Deposit assets into the Sett, and return corresponding shares to the user
    function depositFor(address _recipient, uint256 _amount) public whenNotPaused {
        _depositForWithAuthorization(_recipient, _amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function depositFor(
        address _recipient,
        uint256 _amount,
        bytes32[] memory proof
    ) public whenNotPaused {
        _depositForWithAuthorization(_recipient, _amount, proof);
    }

    /// @notice No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public whenNotPaused {
        _withdraw(_shares);
    }

    /// @notice Convenience function: Withdraw all shares of the sender
    function withdrawAll() external whenNotPaused {
        _withdraw(balanceOf(msg.sender));
    }

    /// ===== Permissioned Actions: Strategy =====

    /// @dev assigns harvest's variable and mints shares to governance and strategist for fees
    function report(uint256 _harvestedAmount, uint256 _harvestTime, uint256 _assetsAtLastHarvest) external whenNotPaused {
        require(msg.sender == strategy, "onlyStrategy");

        _handleFees(_harvestedAmount, _harvestTime);
        
        lastHarvestAmount = _harvestedAmount;
        
        // if we withdrawnAll from strategy and then harvest _assetsAtLastHarvest == 0 therefore dont change assetsAtLastHarvest
        if (_assetsAtLastHarvest !=0) {
            assetsAtLastHarvest = _assetsAtLastHarvest;
        } else if (_assetsAtLastHarvest == 0 && lastHarvestAmount == 0) {
            assetsAtLastHarvest = 0;
        }
        
        lifeTimeEarned += lastHarvestAmount;
        lastHarvestedAt = _harvestTime;
    }

    /// ===== Permissioned Actions: Governance =====

    function setRewards(address _rewards) external whenNotPaused {
        _onlyGovernance();
        rewards = _rewards;
    }

    function setStrategy(address _strategy) external whenNotPaused {
        _onlyGovernance(); 
        /// NOTE: Migrate funds if settings strategy when already existing one
        if(strategy != address(0)){
            require(IStrategy(strategy).balanceOf() == 0, "Please withdrawAll before changing strat");
        }
        strategy = _strategy;
    }

    /// @notice Set minimum threshold of underlying that must be deposited in strategy
    /// @notice Can only be changed by governance
    function setMin(uint256 _min) external whenNotPaused {
        _onlyGovernance();
        require(_min <= MAX, "min should be <= MAX");
        min = _min;
    }

    /// @notice Set management fees
    /// @notice Can only be changed by governance
    function setManagementFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX, "excessive-management-fee");
        managementFee = _fees;
    }

    /// @notice Set maxWithdrawalFee
    /// @notice Can only be changed by governance
    function setMaxWithdrawalFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX, "excessive-withdrawal-fee");
        maxWithdrawalFee = _fees;
    }

    /// @notice Set maxPerformanceFee
    /// @notice Can only be changed by governance
    function setMaxPerformanceFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX, "excessive-performance-fee");
        maxPerformanceFee = _fees;
    }

    /// @notice Change guardian address
    /// @notice Can only be changed by governance
    function setGuardian(address _guardian) external whenNotPaused {
        _onlyGovernance();
        require(_guardian != address(0), "Address cannot be 0x0");
        guardian = _guardian;
    }

    /// ===== Permissioned Functions: Trusted Actors =====

    /// @notice can only be called by governance or strategist
    function setGuestList(address _guestList) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        guestList = BadgerGuestListAPI(_guestList);
    }

    /// @notice can only be called by governance or strategist
    function setWithdrawalFee(uint256 _withdrawalFee) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_withdrawalFee <= maxWithdrawalFee, "base-strategy/excessive-withdrawal-fee");
        withdrawalFee = _withdrawalFee;
    }

    /// @notice can only be called by governance or strategist
    function setPerformanceFeeStrategist(uint256 _performanceFeeStrategist) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_performanceFeeStrategist <= maxPerformanceFee, "base-strategy/excessive-strategist-performance-fee");
        performanceFeeStrategist = _performanceFeeStrategist;
    }

    /// @notice can only be called by governance or strategist
    function setPerformanceFeeGovernance(uint256 _performanceFeeGovernance) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_performanceFeeGovernance <= maxPerformanceFee, "base-strategy/excessive-governance-performance-fee");
        performanceFeeGovernance = _performanceFeeGovernance;
    }

    /// @dev Withdraws all funds from Strategy and deposits into vault
    /// @notice can only be called by governance or strategist
    function withdrawToVault() public {
        _onlyGovernanceOrStrategist();
        IStrategy(strategy).withdrawToVault();
    }

    /// @notice can only be called by governance or strategist
    function withdrawOther(address _token) public {
        _onlyGovernanceOrStrategist();
        uint256 _balance = IStrategy(strategy).withdrawOther(_token);

        IERC20Upgradeable(_token).safeTransfer(governance, _balance);
    }

    /// @notice Transfer the underlying available to be claimed to the strategy
    /// @notice The strategy will use for yield-generating activities
    function earn() public whenNotPaused {
        _onlyAuthorizedActors();

        uint256 _bal = available();
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).earn();
    }

    /// @dev Emit event tracking current full price per share
    /// @dev Provides a pure on-chain way of approximating APY
    function trackFullPricePerShare() external whenNotPaused {
        _onlyAuthorizedActors();
        emit FullPricePerShareUpdated(getPricePerFullShare(), now, block.number);
    }

    /// @dev Transfer an amount of the specified token from the vault to the sender.
    /// @dev Token balance are never meant to exist in the controller, this is purely a safeguard.
    function inCaseStrategyTokenGetStuck(address _strategy, address _token)
        public
    {
        _onlyGovernanceOrStrategist();
        IStrategy(_strategy).withdrawOther(_token);
    }


    function pause() external {
        _onlyAuthorizedPausers();
        _pause();
    }

    function unpause() external {
        _onlyGovernance();
        _unpause();
    }

    /// ===== Internal Implementations =====

    /// @dev Calculate the number of shares to issue for a given deposit
    /// @dev This is based on the realized value of underlying assets between Sett & associated Strategy
    // @dev deposit for msg.sender
    function _deposit(uint256 _amount) internal {
        _depositFor(msg.sender, _amount);
    }

    function _depositFor(address recipient, uint256 _amount) internal virtual {
        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(recipient, shares);
    }

    function _depositWithAuthorization(uint256 _amount, bytes32[] memory proof) internal virtual {
        if (address(guestList) != address(0)) {
            require(guestList.authorized(msg.sender, _amount, proof), "guest-list-authorization");
        }
        _deposit(_amount);
    }

    function _depositForWithAuthorization(
        address _recipient,
        uint256 _amount,
        bytes32[] memory proof
    ) internal virtual {
        if (address(guestList) != address(0)) {
            require(guestList.authorized(_recipient, _amount, proof), "guest-list-authorization");
        }
        _depositFor(_recipient, _amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    /// @notice Processes withdrawal fee if present
    function _withdraw(uint256 _shares) internal virtual {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _toWithdraw = r.sub(b);
            IStrategy(strategy).withdraw(_toWithdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _toWithdraw) {
                r = b.add(_diff);
            }
        }

        // Process withdrawal fee
        uint256 _fee = _processFee(r, withdrawalFee);
        IERC20Upgradeable(token).safeTransfer(rewards, _fee);

        token.safeTransfer(msg.sender, r.sub(_fee));
    }

    /// @dev function to process an arbitrary fee
    /// @return fee : amount of fees to take
    function _processFee(
        uint256 amount,
        uint256 feeBps
    ) internal returns (uint256 fee) {
        if (feeBps == 0) {
            return 0;
        }
        fee = amount.mul(feeBps).div(MAX);
        return fee;
    }

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount)
        internal
        returns (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        )
    {
        governancePerformanceFee = _processFee(
            _amount,
            performanceFeeGovernance
        );

        strategistPerformanceFee = _processFee(
            _amount,
            performanceFeeStrategist
        );

        return (governancePerformanceFee, strategistPerformanceFee);
    }

    /// @dev mints performance fees shares for governance and strategist
    function _mintPerformanceFeeSharesFor(address recipient, uint256 _amount, uint256 _pool) internal {
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(recipient, shares);
    }

    /// @dev called by function report to handle minting of 
    function _handleFees(uint256 _harvestedAmount, uint256 _harvestTime) internal {
        
        (uint256 feeStrategist, uint256 feeGovernance) = _processPerformanceFees(_harvestedAmount);
        uint256 duration = _harvestTime.sub(lastHarvestedAt);
        uint256 management_fee = managementFee.mul(balance()).mul(duration).div(SECS_PER_YEAR).div(MAX);
        uint256 totalGovernanceFee = feeGovernance + management_fee;

        // subtracting totalGovernanceFee and feeStrategist from pool as they are already present in vault
        uint256 _pool = balance().sub(totalGovernanceFee).sub(feeStrategist);

        if (totalGovernanceFee != 0) {
            _mintPerformanceFeeSharesFor(governance, totalGovernanceFee, _pool);
        }

        if (feeStrategist != 0 && strategist != address(0)) {
            /// NOTE: adding feeGovernance backed to _pool as shares would have been issued for it.
            _mintPerformanceFeeSharesFor(strategist, feeStrategist, _pool.add(totalGovernanceFee));
        }

    }

}
