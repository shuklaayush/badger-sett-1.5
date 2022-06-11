// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
