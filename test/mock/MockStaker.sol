// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract MockStaker {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => mapping(address => uint256)) public balanceOf;

    function stake(address token, uint256 amount) public {
        balanceOf[token][msg.sender] += amount;
        IERC20Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function unstake(address token, uint256 amount) public {
        balanceOf[token][msg.sender] -= amount;
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    }
}
