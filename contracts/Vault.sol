// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./lib/SettAccessControl.sol";

import {IVault} from "../interfaces/badger/IVault.sol";
import {IStrategy} from "../interfaces/badger/IStrategy.sol";
import {IERC20Detailed} from "../interfaces/erc20/IERC20Detailed.sol";
import {BadgerGuestListAPI} from "../interfaces/yearn/BadgerGuestlistApi.sol";

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
        - Vault mints shares for performanceFees and managementFee to the respective recipient (treasury, strategist)
        - withdrawal fees is transferred to the rewards address set
    * Permission:
        - Strategist can now set performance, withdrawal and management fees
        - Governance will determine maxPerformanceFee, maxWithdrawalFee, maxManagementFee that can be set to prevent rug of funds.
    * Strategy would take the actors from the vault it is connected to
    * All goverance related fees goes to treasury
*/

contract Vault is ERC20Upgradeable, SettAccessControl, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    uint256 constant ONE_ETH = 1e18;

    /// ===== Storage Variables ====

    IERC20Upgradeable public token; // Token used for deposits
    BadgerGuestListAPI public guestList; // guestlist when vault is in experiment/ guarded state

    bool public pausedDeposit; // false by default Allows to only block deposits, use pause for the normal pause state

    address public strategy; // address of the strategy connected to the vault
    address public guardian; // guardian of vault and strategy
    address public treasury; // set by governance ... any fees go there

    address public badgerTree; // Address we send tokens too via reportAdditionalTokens

    /// @dev name and symbol prefixes for lpcomponent token of vault
    string internal constant _defaultNamePrefix = "Badger Sett ";
    string internal constant _symbolSymbolPrefix = "b";

    /// Params to track autocompounded rewards
    uint256 public lifeTimeEarned; // keeps track of total earnings
    uint256 public lastHarvestedAt; // timestamp of the last harvest
    uint256 public lastHarvestAmount; // amount harvested during last harvest
    uint256 public assetsAtLastHarvest; // assets for which the harvest took place.

    mapping (address => uint256) public additionalTokensEarned;

    /// Fees ///
    /// @notice all fees will be in bps
    uint256 public performanceFeeGovernance; // Perf fee sent to `treasury`
    uint256 public performanceFeeStrategist; // Perf fee sent to `strategist`
    uint256 public withdrawalFee; // fee issued to `treasury` on withdrawal 
    uint256 public managementFee; // fee issued to `treasury` on report (typically on harvest, but only if strat is autocompounding)

    uint256 public maxPerformanceFee; // maximum allowed performance fees
    uint256 public maxWithdrawalFee; // maximum allowed withdrawal fees
    uint256 public maxManagementFee; // maximum allowed management fees

    uint256 public toEarnBps; // NOTE: in BPS, minimum amount of token to deposit into strategy when earn is called

    /// ===== Contants ====
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant SECS_PER_YEAR = 31_556_952; // 365.2425 days

    /// ===== Events ====
    // Emitted when a token is sent to the badgerTree for emissions
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    // Emitted during a report, when there has been an increase in pricePerFullShare (ppfs)
    event Harvested(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);

    event SetTreasury(address indexed newTreasury);
    event SetStrategy(address indexed newStrategy);
    event SetToEarnBps(uint256 newEarnToBps);
    event SetMaxWithdrawalFee(uint256 newMaxWithdrawalFee);
    event SetMaxPerformanceFee(uint256 newMaxPerformanceFee);
    event SetMaxManagementFee(uint256 newMaxManagementFee);
    event SetGuardian(address indexed newGuardian);
    event SetGuestList(address indexed newGuestList);
    event SetWithdrawalFee(uint256 newWithdrawalFee);
    event SetPerformanceFeeStrategist(uint256 newPerformanceFeeStrategist);
    event SetPerformanceFeeGovernance(uint256 newPerformanceFeeGovernance);
    event SetManagementFee(uint256 newManagementFee);
    event PauseDeposits(address pausedBy);
    event UnpauseDeposits(address pausedBy);

    function initialize(
        address _token,
        address _governance,
        address _keeper,
        address _guardian,
        address _treasury,
        address _strategist,
        address _badgerTree,
        string memory _name,
        string memory _symbol,
        uint256[4] memory _feeConfig
    ) public initializer whenNotPaused {
        require(_token != address(0)); // dev: _token address should not be zero
        require(_governance != address(0)); // dev: _governance address should not be zero
        require(_keeper != address(0)); // dev: _keeper address should not be zero
        require(_guardian != address(0)); // dev: _guardian address should not be zero
        require(_treasury != address(0)); // dev: _treasury address should not be zero
        require(_strategist != address(0)); // dev: _strategist address should not be zero
        require(_badgerTree != address(0)); // dev: _badgerTree address should not be zero

        string memory name;
        string memory symbol;

        // If they are non empty string we'll use the custom names
        // Else just add the default prefix
        IERC20Detailed namedToken = IERC20Detailed(_token);

        if(keccak256(abi.encodePacked(_name)) != keccak256("")) {
            name = _name;
        } else {
            name = string(abi.encodePacked(_defaultNamePrefix, namedToken.name()));
        }

        if (keccak256(abi.encodePacked(_symbol)) != keccak256("")) {
            symbol = _symbol;
        } else {
            symbol = string(abi.encodePacked(_symbolSymbolPrefix, namedToken.symbol()));
         }

        // Initializing the lpcomponent token
        __ERC20_init(name, symbol);
        // Initialize the other contracts
        __Pausable_init();
        __ReentrancyGuard_init();

        token = IERC20Upgradeable(_token);
        governance = _governance;
        treasury = _treasury;
        strategist = _strategist;
        keeper = _keeper;
        guardian = _guardian;
        badgerTree = _badgerTree;

        lastHarvestedAt = block.timestamp; // setting initial value to the time when the vault was deployed

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];
        managementFee = _feeConfig[3];
        maxPerformanceFee = 3_000; // 30% maximum performance fee // We usually do 20, so this is insanely high already
        maxWithdrawalFee = 100; // 1% maximum withdrawal fee
        maxManagementFee = 200; // 2% maximum management fee

        toEarnBps = 10_000; // initial value of toEarnBps
    }

    /// ===== Modifiers ====

    function _onlyAuthorizedPausers() internal view {
        require(msg.sender == guardian || msg.sender == governance, "onlyPausers");
    }

    function _onlyStrategy() internal view {
        require(msg.sender == strategy, "onlyStrategy");
    }

    /// ===== View Functions =====
    
    function version() external view returns (string memory) {
        return "1.5";
    }

    /// @dev Return the price of a share, denominated in ONE_ETH
    function getPricePerFullShare() public view returns (uint256) {
        if (totalSupply() == 0) {
            return ONE_ETH;
        }
        return balance().mul(ONE_ETH).div(totalSupply());
    }

    /// @notice Return the total balance of the underlying token within the system
    /// @notice Sums the balance in the Sett and the Strategy
    function balance() public view returns (uint256) {
        return token.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    /// @notice Defines how much of the Setts' underlying can be borrowed by the Strategy for use
    /// @notice Custom logic in here for how much the vault allows to be borrowed
    /// @notice Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint256) {
        return token.balanceOf(address(this)).mul(toEarnBps).div(MAX_BPS);
    }

    /// ===== Public Actions =====

    /// @notice Deposit assets into the Sett, and return corresponding shares to the user
    function deposit(uint256 _amount) external whenNotPaused {
        _depositWithAuthorization(_amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function deposit(uint256 _amount, bytes32[] memory proof) external whenNotPaused {
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
    function depositFor(address _recipient, uint256 _amount) external whenNotPaused {
        _depositForWithAuthorization(_recipient, _amount, new bytes32[](0));
    }

    /// @notice Deposit variant with proof for merkle guest list
    function depositFor(
        address _recipient,
        uint256 _amount,
        bytes32[] memory proof
    ) external whenNotPaused {
        _depositForWithAuthorization(_recipient, _amount, proof);
    }

    /// @notice No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) external whenNotPaused {
        _withdraw(_shares);
    }

    /// @notice Convenience function: Withdraw all shares of the sender
    function withdrawAll() external whenNotPaused {
        _withdraw(balanceOf(msg.sender));
    }

    /// ===== Permissioned Actions: Strategy =====

    /// @dev assigns harvest's variable and mints shares to governance and strategist for fees for autocompounded rewards
    /// @notice you are trusting the strategy to report the correct amount
    function reportHarvest(
        uint256 _harvestedAmount
    ) external whenNotPaused nonReentrant {
        _onlyStrategy();

        uint256 harvestTime = block.timestamp;
        uint256 assetsAtHarvest = balance().sub(_harvestedAmount); // Must be less than or equal or revert

        _handleFees(_harvestedAmount, harvestTime);

        // Updated lastHarvestAmount
        lastHarvestAmount = _harvestedAmount;

        // if we withdrawAll
        // we will have some yield left
        // having 0 for assets will inflate APY
        // Instead, have the last harvest report with the previous assets
        // And if you end up harvesting again, that report will have both 0s
        if (assetsAtHarvest != 0) {
            assetsAtLastHarvest = assetsAtHarvest;
        } else if (_harvestedAmount == 0) {
            // If zero
            assetsAtLastHarvest = 0;
        }

        lifeTimeEarned = lifeTimeEarned.add(_harvestedAmount);
        // Update time either way
        lastHarvestedAt = harvestTime;

        emit Harvested(address(token), _harvestedAmount, block.number, block.timestamp);
    }

    /// @dev assigns harvest's variable and mints shares to governance and strategist for fees for non want rewards
    /// NOTE: non want rewards would remain in the strategy and can be withdrawn using
    // This function is called after the strat sends us the tokens
    // We have to receive the tokens as those are protected and no-one can pull those funds
    function reportAdditionalToken(address _token) external whenNotPaused nonReentrant {
        _onlyStrategy();
        require(address(token) != _token, "No want");
        uint256 tokenBalance = IERC20Upgradeable(_token).balanceOf(address(this));

        additionalTokensEarned[_token] = additionalTokensEarned[_token].add(tokenBalance);

        // We may have more, but we still report only what the strat sent
        uint256 governanceRewardsFee = _calculateFee(tokenBalance, performanceFeeGovernance);
        uint256 strategistRewardsFee = _calculateFee(tokenBalance, performanceFeeStrategist);

        IERC20Upgradeable(_token).safeTransfer(treasury, governanceRewardsFee);
        IERC20Upgradeable(_token).safeTransfer(strategist, strategistRewardsFee);

        // Send rest to tree
        uint256 newBalance = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(badgerTree, newBalance);
        emit TreeDistribution(_token, newBalance, block.number, block.timestamp);
    }

    /// ===== Permissioned Actions: Governance =====

    /// @dev Changes the treasury, recipient of management and performanceFeeGovernance
    function setTreasury(address _treasury) external whenNotPaused {
        _onlyGovernance();
        require(_treasury != address(0), "Address 0");

        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    /// @dev Changes the Strategy
    /// @notice This is arguably a rug vector, pay extreme attention to the next strategy being set
    /// @notice Changing the strategy should happen via timelock
    function setStrategy(address _strategy) external whenNotPaused {
        _onlyGovernance();
        require(_strategy != address(0), "Address 0");


        /// NOTE: Migrate funds if settings strategy when already existing one
        if (strategy != address(0)) {
            require(IStrategy(strategy).balanceOf() == 0, "Please withdrawToVault before changing strat");
        }
        strategy = _strategy;
        emit SetStrategy(_strategy);
    }

    /// @notice Set minimum threshold of underlying that must be deposited in strategy
    /// @notice Can only be changed by governance
    function setToEarnBps(uint256 _newToEarnBps) external whenNotPaused {
        _onlyGovernance();
        require(_newToEarnBps <= MAX_BPS, "toEarnBps should be <= MAX_BPS");

        toEarnBps = _newToEarnBps;
        emit SetToEarnBps(_newToEarnBps);
    }

    /// @notice Set maxWithdrawalFee
    /// @notice Can only be changed by governance
    function setMaxWithdrawalFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX_BPS, "Excessive withdrawal fee");

        maxWithdrawalFee = _fees;
        emit SetMaxWithdrawalFee(_fees);
    }

    /// @notice Set maxPerformanceFee
    /// @notice Can only be changed by governance
    function setMaxPerformanceFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX_BPS, "Excessive performance fee");

        maxPerformanceFee = _fees;
        emit SetMaxPerformanceFee(_fees);
    }

    /// @notice Set maxPerformanceFee
    /// @notice Can only be changed by governance
    function setMaxManagementFee(uint256 _fees) external whenNotPaused {
        _onlyGovernance();
        require(_fees <= MAX_BPS, "Excessive management fee");

        maxManagementFee = _fees;
        emit SetMaxManagementFee(_fees);
    }

    /// @notice Change guardian address
    /// @notice Can only be changed by governance
    function setGuardian(address _guardian) external whenNotPaused {
        _onlyGovernance();
        require(_guardian != address(0), "Address cannot be 0x0");

        guardian = _guardian;
        emit SetGuardian(_guardian);
    }

    /// ===== Permissioned Functions: Trusted Actors =====

    /// @dev Changes the guestList, used to gate or limit deposits
    /// @notice can only be called by governance or strategist
    function setGuestList(address _guestList) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        guestList = BadgerGuestListAPI(_guestList);
        emit SetGuestList(_guestList);
    }

    /// @dev Sets the withdrawalFee, which is taken in want at the time of withdrawin
    /// @dev the fee taken in want is then used to issue shares
    /// @notice can also be called by strategist because bounds are set by governance
    function setWithdrawalFee(uint256 _withdrawalFee) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_withdrawalFee <= maxWithdrawalFee, "Excessive withdrawal fee");
        withdrawalFee = _withdrawalFee;
        emit SetWithdrawalFee(_withdrawalFee);
    }

    /// @dev Sets the performance fee for the strategist, taken at time of report
    /// @notice can also be called by strategist because bounds are set by governance
    function setPerformanceFeeStrategist(uint256 _performanceFeeStrategist) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_performanceFeeStrategist <= maxPerformanceFee, "Excessive strategist performance fee");
        performanceFeeStrategist = _performanceFeeStrategist;
        emit SetPerformanceFeeStrategist(_performanceFeeStrategist);
    }

    /// @dev Sets the performance fee for the governance, taken at time of report
    /// @notice Governance fees are paid to treasury
    /// @notice can also be called by strategist because bounds are set by governance
    function setPerformanceFeeGovernance(uint256 _performanceFeeGovernance) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_performanceFeeGovernance <= maxPerformanceFee, "Excessive governance performance fee");
        performanceFeeGovernance = _performanceFeeGovernance;
        emit SetPerformanceFeeGovernance(_performanceFeeGovernance);
    }

    /// @notice Set management fees, which are calculated during reports and issued to treasury
    /// @notice can also be called by strategist because bounds are set by governance
    function setManagementFee(uint256 _fees) external whenNotPaused {
        _onlyGovernanceOrStrategist();
        require(_fees <= maxManagementFee, "Excessive management fee");
        managementFee = _fees;
        emit SetManagementFee(_fees);
    }

    /// @dev Withdraws all funds from Strategy and deposits into vault
    /// @notice can only be called by governance or strategist
    /// @notice This is basically withdrawAll
    /// @notice We renamed it due to withdrawAll being used to allow a user to withdraw all their funds
    function withdrawToVault() external {
        _onlyGovernanceOrStrategist();
        IStrategy(strategy).withdrawToVault();
    }

    /// @dev Used to withdraw an extra token and send it to governance
    function sweepExtraToken(address _token) external {
        _onlyGovernanceOrStrategist();
        require(address(token) != _token, "No want");

        IStrategy(strategy).withdrawOther(_token);
        // Send all `_token` we have
        // Safe because `withdrawOther` will revert on protected tokens  
        // Done this way works for both a donation to strategy or to vault
        IERC20Upgradeable(_token).safeTransfer(governance, IERC20Upgradeable(_token).balanceOf(address(this)));
    }
    
    /// @dev Used to emit an extra token (e.g. airdrop), take fees and send to badgerTree for emission
    /// @notice This function is just calling `emitNonProtectedToken` on the BaseStrategy see the code there for details
    function emitNonProtectedToken(address _token) external {
        _onlyGovernanceOrStrategist();

        IStrategy(strategy).emitNonProtectedToken(_token);
    }

    /// @dev Transfer the underlying available to be claimed to the strategy
    /// @notice The strategy will use for yield-generating activities
    function earn() external whenNotPaused {
        require(!pausedDeposit, "pausedDeposit"); // dev: deposits are paused, we don't earn as well
        _onlyAuthorizedActors();

        uint256 _bal = available();
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).earn();
    }

    /// @dev Pauses deposits
    /// @notice Deposits have an extra check to be paused, pause() will instead always pause everything
    function pauseDeposits() external {
        _onlyAuthorizedPausers();
        pausedDeposit = true;
        emit PauseDeposits(msg.sender);
    }
    
    /// @dev Resume deposits
    function unpauseDeposits() external {
        _onlyGovernance();
        pausedDeposit = false;
        emit UnpauseDeposits(msg.sender);
    }

    /// @dev Pauses everything
    /// @notice Emits event Paused(address account); from OZ Parent Contract
    function pause() external {
        _onlyAuthorizedPausers();
        _pause();
    }

    /// @dev Unpauses everything
    /// @notice Emits event Unpaused(address account); from OZ Parent Contract
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

    function _depositFor(address _recipient, uint256 _amount) internal nonReentrant {
        require(_recipient != address(0), "Address 0");
        require(_amount != 0, "Amount 0");
        require(!pausedDeposit, "pausedDeposit"); // dev: deposits are paused

        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _mintSharesFor(_recipient, _after.sub(_before), _pool);
    }

    function _depositWithAuthorization(uint256 _amount, bytes32[] memory proof) internal {
        _depositForWithAuthorization(msg.sender, _amount, proof);
    }

    function _depositForWithAuthorization(
        address _recipient,
        uint256 _amount,
        bytes32[] memory proof
    ) internal {
        if (address(guestList) != address(0)) {
            require(guestList.authorized(_recipient, _amount, proof), "GuestList: Not Authorized");
        }
        _depositFor(_recipient, _amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    /// @notice Processes withdrawal fee if present
    function _withdraw(uint256 _shares) internal nonReentrant {
        require(_shares != 0, "0 Shares");

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
        uint256 _fee = _calculateFee(r, withdrawalFee);

        // Send funds to user
        token.safeTransfer(msg.sender, r.sub(_fee));

        // After you burned the shares, and you have sent the funds, adding here is equivalent to depositing
        // Process withdrawal fee
        _mintSharesFor(treasury, _fee, balance().sub(_fee));
    }

    /// @dev function to process an arbitrary fee
    /// @return fee : amount of fees to take
    function _calculateFee(uint256 amount, uint256 feeBps) internal pure returns (uint256 fee) {
        if (feeBps == 0) {
            return 0;
        }
        fee = amount.mul(feeBps).div(MAX_BPS);
        return fee;
    }

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _calculatePerformanceFee(uint256 _amount)
        internal
        view
        returns (uint256 governancePerformanceFee, uint256 strategistPerformanceFee)
    {
        governancePerformanceFee = _calculateFee(_amount, performanceFeeGovernance);

        strategistPerformanceFee = _calculateFee(_amount, performanceFeeStrategist);

        return (governancePerformanceFee, strategistPerformanceFee);
    }

    /// @dev mints performance fees shares for governance and strategist
    function _mintSharesFor(
        address recipient,
        uint256 _amount,
        uint256 _pool
    ) internal {
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(recipient, shares);
    }

    /// @dev called by function report to handle minting of
    function _handleFees(uint256 _harvestedAmount, uint256 harvestTime) internal {
        (uint256 feeGovernance, uint256 feeStrategist) = _calculatePerformanceFee(_harvestedAmount);
        uint256 duration = harvestTime.sub(lastHarvestedAt);

        // Management fee is calculated against the assets before harvest, to make it fair to depositors
        uint256 management_fee = managementFee > 0 ? managementFee.mul(balance().sub(_harvestedAmount)).mul(duration).div(SECS_PER_YEAR).div(MAX_BPS) : 0;
        uint256 totalGovernanceFee = feeGovernance.add(management_fee);

        // Pool size is the size of the pool minus the fees, this way 
        // it's equivalent to sending the tokens as rewards after the harvest
        // and depositing them again
        uint256 _pool = balance().sub(totalGovernanceFee).sub(feeStrategist);

        // uint != is cheaper and equivalent to >
        if (totalGovernanceFee != 0) {
            _mintSharesFor(treasury, totalGovernanceFee, _pool);
        }

        if (feeStrategist != 0 && strategist != address(0)) {
            /// NOTE: adding feeGovernance backed to _pool as shares would have been issued for it.
            _mintSharesFor(strategist, feeStrategist, _pool.add(totalGovernanceFee));
        }
    }
}
