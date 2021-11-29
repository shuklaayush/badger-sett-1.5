// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import {BaseStrategy} from "../BaseStrategy.sol";

contract DemoStrategy is BaseStrategy {
    // address public want; // Inherited from BaseStrategy
    // address public lpComponent; // Token that represents ownership in a pool, not always used
    // address public reward; // Token we farm

    /// @notice set using setAutoCompoundRatio()
    // uint256 public autoCompoundRatio = 10_000; // Inherited from BaseStrategy - percentage of rewards converted to want

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    /// @notice Dev must implement
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0];

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
        return "DemoStrategy";
    }

    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](1);
        protectedTokens[0] = want;
        return protectedTokens;
    }

    function _deposit(uint256 _amount) internal override {
        // No-op as we don't do anything
    }

    function _withdrawAll() internal override {
        // No-op as we don't deposit
    }

    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        return _amount;
    }

    function harvest() external override whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();
        // No-op as we don't do anything with funds
        // use autoCompoundRatio here to convert rewards to want ...
        // keep this to get paid!
        // _reportToVault(earned, block.timestamp, balanceOfPool());
        return 0;
    }

    /// @dev function to test harvest -
    // NOTE: want of 1 ether would be minted directly to DemoStrategy and this function would be called
    /// @param amount how much was minted to report
    function test_harvest(uint256 amount) external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        // Amount of want autocompounded after harvest in terms of want
        // keep this to get paid!
        _reportToVault(amount, block.timestamp, balanceOfPool());

        return harvested;
    }

    function balanceOfPool() public view override returns (uint256) {
        return 0;
    }

    function balanceOfRewards() public view override returns (uint256) {
        return 0;
    }
}
