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
  function initialize(
        address _governance,
        address _strategist,
        address _vault,
        address _keeper,
        address _guardian,
        address[1] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _vault,
            _keeper,
            _guardian
        );
        /// @dev Add config here
        want = _wantConfig[0];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        // If you need to set new values that are not constants, set them like so
        // stakingContract = 0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7;
    }

  function getName() external pure override returns (string memory) {
    return "DemoStrategy";
  }

  function getProtectedTokens() public virtual view override returns (address[] memory) {
    address[] memory protectedTokens = new address[](1);
    protectedTokens[0] = want;
    return protectedTokens;
  }

  function _deposit(uint256 _want) internal override {
    // No-op as we don't do anything
  }

  function _withdrawAll() internal override {
    // No-op as we don't deposit
  }

  function _withdrawSome(uint256 _want) internal override returns (uint256) {
    return _want;
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
  function test_harvest() external whenNotPaused returns (uint256 harvested) {
    _onlyAuthorizedActors();

    // Amount of want earned after harvest in terms of want
    uint256 harvestAmount = 1 ether;

    // keep this to get paid!
    _reportToVault(
      harvestAmount,
      block.timestamp,
      balanceOfPool()
    ); 
    
    return harvestAmount;
  }

  function balanceOfPool() public view override returns (uint256) {
    return 0;
  }

  function balanceOfRewards() public view override returns (uint256) {
    return 0;
  }
}