// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IVault {
    function rewards() external view returns (address);

    function report(
        uint256 _harvestedAmount,
        uint256 _harvestTime,
        uint256 _assetsAtLastHarvest
    ) external;

    function reportAdditionalToken(uint256 _amount, address _token) external;

    // Fees
    function performanceFeeGovernance() external view returns (uint256);

    function performanceFeeStrategist() external view returns (uint256);

    function withdrawalFee() external view returns (uint256);

    function managementFee() external view returns (uint256);

    // Actors
    function governance() external view returns (address);

    function keeper() external view returns (address);

    function guardian() external view returns (address);

    function strategist() external view returns (address);
}
