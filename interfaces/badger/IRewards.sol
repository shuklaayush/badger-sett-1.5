/// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

interface IRewards {
    function notifyTransfer(
        address from,
        address to,
        uint256 amount
    ) external;
}
