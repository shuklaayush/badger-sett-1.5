// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IStrategy {
  function balanceOf() external view returns (uint256 balance);
  function balanceOfPool() external view returns (uint256 balance);
  function balanceOfWant() external view returns (uint256 balance);

  function earn(uint256 amount) external;
  function withdraw(uint256 amount) external;
}