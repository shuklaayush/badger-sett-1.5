// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {BaseStrategy} from "../BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address public want; // Inherited from BaseStrategy
    // address public lpComponent; // Token that represents ownership in a pool, not always used
    address public reward; // Token we farm

    uint256 private lossBps;
    uint256 private harvestAmount;

    /// @notice set using setAutoCompoundRatio()
    // uint256 public autoCompoundRatio = 10_000; // Inherited from BaseStrategy - percentage of rewards converted to want

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    /// @notice Dev must implement
    function initialize(address _vault, address[] calldata _tokenConfig)
        public
        initializer
    {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        reward = _tokenConfig[0];

        autoCompoundRatio = 10_000; // Percentage of reward we reinvest into want

        // If you need to set new values that are not constants, set them like so
        // stakingContract = 0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7;

        // If you need to do one-off approvals do them here like so
        // IERC20Upgradeable(reward).safeApprove(
        //     address(DX_SWAP_ROUTER),
        //     type(uint256).max
        // );
    }

    function getName() external pure override returns (string memory) {
        return "MockStrategy";
    }

    function getProtectedTokens()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want;
        protectedTokens[1] = reward;
        return protectedTokens;
    }

    function _isTendable() internal pure override returns (bool) {
        return true;
    }

    function setLossBps(uint256 _lossBps) public {
        lossBps = _lossBps;
    }

    function setHarvestAmount(uint256 _amount) public {
        harvestAmount = _amount;
    }

    function _deposit(uint256 _amount) internal override {}

    function _withdrawAll() internal override {
        // No-op as we don't deposit
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        uint256 loss = (_amount * lossBps) / MAX_BPS;
        IERC20Upgradeable(want).transfer(address(0xdEaD), loss);
        return _amount - loss;
    }

    function _harvest()
        internal
        override
        returns (TokenAmount[] memory harvested)
    {
        uint256 harvestRewardAmount = IERC20Upgradeable(reward).balanceOf(
            address(this)
        );

        _reportToVault(harvestAmount);
        if (harvestRewardAmount > 0) {
            _processExtraToken(reward, harvestRewardAmount);
        }

        harvested = new TokenAmount[](2);
        harvested[0] = TokenAmount(want, harvestAmount);
        harvested[1] = TokenAmount(reward, harvestRewardAmount);
    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend()
        internal
        view
        override
        returns (TokenAmount[] memory tended)
    {
        // Nothing tended
        tended = new TokenAmount[](2);
        tended[0] = TokenAmount(want, 0);
        tended[1] = TokenAmount(reward, 0);
        return tended;
    }

    function balanceOfPool() public pure override returns (uint256) {
        return 0;
    }

    function balanceOfRewards()
        external
        view
        override
        returns (TokenAmount[] memory rewards)
    {
        // Rewards are 0
        rewards = new TokenAmount[](2);
        rewards[0] = TokenAmount(want, 0);
        rewards[1] = TokenAmount(reward, 0);
        return rewards;
    }
}
