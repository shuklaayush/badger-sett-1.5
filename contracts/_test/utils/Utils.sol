// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

abstract contract Utils {
    function getAddress(string memory _name)
        internal
        pure
        returns (address addr_)
    {
        addr_ = address(uint160(uint256(keccak256(bytes(_name)))));
    }
}
