// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {MockToken} from "./mocks/MockToken.sol";

abstract contract Config {
    address internal immutable WANT = address(new MockToken("want", "WANT"));

    address[] internal EMITS = [address(new MockToken("emit", "EMIT"))];

    uint256 public constant PERFORMANCE_FEE_GOVERNANCE = 1_500;
    uint256 public constant PERFORMANCE_FEE_STRATEGIST = 1_000;
    uint256 public constant WITHDRAWAL_FEE = 10;
    uint256 public constant MANAGEMENT_FEE = 2;
}
