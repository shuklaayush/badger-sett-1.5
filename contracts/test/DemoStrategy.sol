// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import {BaseStrategy} from "../BaseStrategy.sol";

contract DemoStrategy is BaseStrategy {

  function getName() external pure override returns (string memory) {
    return "DemoStrategy";
  }

  function getProtectedTokens() public virtual view override returns (address[] memory) {
    address[] memory protectedTokens = new address[](1);
    protectedTokens[0] = want;
  }

  function _deposit(uint256 _want) internal override {
    // No-op as we don't do anything
  }

  function _withdrawAll() internal override {
    // No-op as we don't deposit
  }

  function _withdrawSome(uint256 _want) internal override returns (uint256) {
    return balanceOfWant();
  }

  function harvest() external override returns (uint256 harvested) {
    // No-op as we don't do anything with funds
  }


  function balanceOfPool() public view override returns (uint256) {
    return 0;
  }

  function earn(uint256 _want) external override {
    // No-op
  }
}