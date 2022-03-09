// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {IVault} from "../../interfaces/badger/IVault.sol";

contract MaliciousToken is ERC20Upgradeable {
    bool private hit;

    function initialize(address[] memory holders, uint256[] memory balances) public initializer {
        __ERC20_init("badger.finance Malicious Token", "MALT");
        require(holders.length == balances.length, "Constructor array size mismatch");
        for (uint256 i = 0; i < holders.length; i++) {
            _mint(holders[i], balances[i]);
        }
    }

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
