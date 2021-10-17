// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IVault {
  
  function rewards() external returns (address);
  
  function report(
    uint256 _harvestedAmount, 
    uint256 _harvestTime, 
    uint256 _assetsAtLastHarvest, 
    uint256 feeStrategist, 
    uint256 feeGovernance
  ) external;

}