// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";

import "./lib/SettAccessControlDefended.sol";

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
        - 
*/

contract Vault is IVault, ERC20Upgradeable, SettAccessControlDefended, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public token;

    uint256 public min;
    uint256 public constant max = 10000;

    mapping(address => uint256) public blockLock;

    address public strategy; // address of the strategy connected to the vault
    address public guardian;
    
    address public override rewards;

    /// @dev name and symbol prefixes for lpcomponent token of vault
    string internal constant _defaultNamePrefix = "Badger Sett ";
    string internal constant _symbolSymbolPrefix = "b";

    BadgerGuestListAPI public guestList; // guestlist when vault is in experiment/ guarded state

    event FullPricePerShareUpdated(uint256 value, uint256 indexed timestamp, uint256 indexed blockNumber);

    uint256 public lifeTimeEarned; // keeps track of total earnings
    uint256 public lastHarvestedAt; // timestamp of the last harvest

    uint256 public lastHarvestAmount; // amount harvested during last harvest
    uint256 public assetsAtLastHarvest; // assets for which the harvest took place.

    function initialize(
        address _token,
        address _governance,
        address _keeper,
        address _guardian,
        bool _overrideTokenName,
        string memory _namePrefix,
        string memory _symbolPrefix
    ) public initializer whenNotPaused {

        require(_token != address(0), "Token address should not be 0x0");

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
        strategist = address(0);
        keeper = _keeper;
        guardian = _guardian;

        min = 9500;

        emit FullPricePerShareUpdated(getPricePerFullShare(), now, block.number);
    }

    /// ===== Modifiers ====


    function _onlyAuthorizedPausers() internal view {
        require(msg.sender == guardian || msg.sender == governance, "onlyPausers");
    }

    function _blockLocked() internal view {
        require(blockLock[msg.sender] < block.number, "blockLocked");
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
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    /// ===== Public Actions =====

    /// @notice Deposit assets into the Sett, and return corresponding shares to the user
    /// @notice Only callable by EOA accounts that pass the _defend() check
    function deposit(uint256 _amount) public whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _depositWithAuthorization(_amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function deposit(uint256 _amount, bytes32[] memory proof) public whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _depositWithAuthorization(_amount, proof);
    }

    /// @notice Convenience function: Deposit entire balance of asset into the Sett, and return corresponding shares to the user
    /// @notice Only callable by EOA accounts that pass the _defend() check
    function depositAll() external whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _depositWithAuthorization(token.balanceOf(msg.sender), new bytes32[](0));
    }

    /// @notice DepositAll variant with proof for merkle guest list
    function depositAll(bytes32[] memory proof) external whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _depositWithAuthorization(token.balanceOf(msg.sender), proof);
    }

    /// @notice Deposit assets into the Sett, and return corresponding shares to the user
    /// @notice Only callable by EOA accounts that pass the _defend() check
    function depositFor(address _recipient, uint256 _amount) public whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(_recipient);
        _depositForWithAuthorization(_recipient, _amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function depositFor(
        address _recipient,
        uint256 _amount,
        bytes32[] memory proof
    ) public whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(_recipient);
        _depositForWithAuthorization(_recipient, _amount, proof);
    }

    /// @notice No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _withdraw(_shares);
    }

    /// @notice Convenience function: Withdraw all shares of the sender
    function withdrawAll() external whenNotPaused {
        _defend();
        _blockLocked();

        _lockForBlock(msg.sender);
        _withdraw(balanceOf(msg.sender));
    }

    /// ===== Permissioned Actions: Strategy =====

    function report(uint256 _harvestedAmount, uint256 _harvestTime, uint256 _assetsAtLastHarvest, uint256 feeStrategist, uint256 feeGovernance) external override whenNotPaused {
        require(msg.sender == strategy, "onlyStrategy");

        lastHarvestedAt = _harvestTime;
        lastHarvestAmount = _harvestedAmount;
        
        // if we withdrawnAll from strategy and then harvest _assetsAtLastHarvest == 0 therefore dont change assetsAtLastHarvest
        if (_assetsAtLastHarvest !=0) {
            assetsAtLastHarvest = _assetsAtLastHarvest;
        } else if (_assetsAtLastHarvest == 0 && lastHarvestAmount == 0) {
            assetsAtLastHarvest = 0;
        }
        
        lifeTimeEarned += lastHarvestAmount;

        if (feeGovernance != 0) {
            _mint(governance, feeGovernance);
        }

        // NOTE: strategist should be same of both vault and strategy
        // NOTE: if strategist on vault changes, strategist on strategy should change and vice-versa
        if (feeStrategist != 0) {
            _mint(strategist, feeStrategist);
        }
    }

    /// ===== Permissioned Actions: Governance =====

    function setRewards(address _rewards) external whenNotPaused {
        _onlyGovernance();
        rewards = _rewards;
    }

    function setStrategy(address _strategy) external whenNotPaused {
        _onlyGovernance();
        // TODO: Migrate funds if settings strategy when already existing one
        if(strategy != address(0)){
            require(IStrategy(strategy).balanceOf() == 0, "Please withdrawAll before changing strat");
        }
        strategy = _strategy;
    }

    function setGuestList(address _guestList) external whenNotPaused {
        _onlyGovernance();
        guestList = BadgerGuestListAPI(_guestList);
    }

    /// @notice Set minimum threshold of underlying that must be deposited in strategy
    /// @notice Can only be changed by governance
    function setMin(uint256 _min) external whenNotPaused {
        _onlyGovernance();
        require(_min <= max, "min should be <= max");
        min = _min;
    }

    /// @notice Change guardian address
    /// @notice Can only be changed by governance
    function setGuardian(address _guardian) external whenNotPaused {
        _onlyGovernance();
        require(_guardian != address(0), "Address cannot be 0x0");
        guardian = _guardian;
    }

    /// ===== Permissioned Functions: Trusted Actors =====

    /// @dev Withdraws all funds from Strategy and deposits into vault
    /// @notice can only be done by governance or strategist
    function withdrawToVault() public {
        _onlyGovernanceOrStrategist();
        IStrategy(strategy).withdrawToVault();
    }

    function withdrawOther(address _token) public {
        _onlyGovernanceOrStrategist();
        uint256 balance = IStrategy(strategy).withdrawOther(_token);

        IERC20Upgradeable(_token).safeTransfer(governance, balance);
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

        token.safeTransfer(msg.sender, r);
    }

    function _lockForBlock(address account) internal {
        blockLock[account] = block.number;
    }

    /// ===== ERC20 Overrides =====

    /// @dev Add blockLock to transfers, users cannot transfer tokens in the same block as a deposit or withdrawal.
    function transfer(address recipient, uint256 amount) public virtual override whenNotPaused returns (bool) {
        _blockLocked();
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override whenNotPaused returns (bool) {
        _blockLocked();
        return super.transferFrom(sender, recipient, amount);
    }
}
