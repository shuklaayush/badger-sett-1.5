// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
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
}
