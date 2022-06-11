// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {MockToken} from "./MockToken.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

contract MaliciousToken is MockToken {
    bool private hit;

    constructor(string memory _name, string memory _symbol)
        MockToken(_name, _symbol)
    {}

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool success) {
        if (!hit) {
            hit = true;
            IVault(msg.sender).deposit(amount);
            return true;
        }
        return super.transferFrom(from, to, amount);
    }
}
