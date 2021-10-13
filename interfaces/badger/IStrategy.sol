// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IStrategy {
  function balanceOf() external view returns (uint256 balance);
  function balanceOfPool() external view returns (uint256 balance);
  function balanceOfWant() external view returns (uint256 balance);

  function earn() external;
  function withdraw(uint256 amount) external;
  function withdrawToVault() external returns (uint256 balance);
  function withdrawOther(address _asset) external returns (uint256 balance);

  function balanceOfRewards() external view returns (uint256);

  /// @notice balanceofRewards and autocompound ratio 
  /// track harvest and everytime a harvest is bad 
  /// - eth_call geth node vs oracle 
  /// registry shows all harvest of expected vs real value
}