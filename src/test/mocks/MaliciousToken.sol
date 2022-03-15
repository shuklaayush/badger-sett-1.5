// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {IVault} from "../../interfaces/IVault.sol";

contract MaliciousToken is ERC20 {
    bool private hit;

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {}

    /// @dev Open minting capabilities
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /// @dev Open burning capabilities, from any account
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

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
