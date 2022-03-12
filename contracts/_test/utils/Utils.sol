// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {Vm} from "forge-std/Vm.sol";

abstract contract MulticallUtils {
    Vm constant vmUtils =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // TODO: Default to 99?
    function getChainIdOfHead() public returns (uint256 chainId_) {
        string[] memory inputs = new string[](2);
        inputs[0] = "bash";
        inputs[1] = "scripts/chain-id.sh";
        chainId_ = abi.decode(vmUtils.ffi(inputs), (uint256));
    }
}

/*
TODO
- Custom errors
*/
