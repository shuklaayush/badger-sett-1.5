// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;

import {Test as TestBase} from "forge-std/Test.sol";

import {IntervalUint256, IntervalUint256Utils} from "./libraries/IntervalUint256.sol";

contract Test is TestBase {
    // =====================
    // ===== Libraries =====
    // =====================

    using IntervalUint256Utils for IntervalUint256;

    // ==========================
    // ===== Util Functions =====
    // ==========================

    function getAddress(string memory _name)
        internal
        pure
        returns (address addr_)
    {
        addr_ = address(uint160(uint256(keccak256(bytes(_name)))));
    }

    // ========================
    // ===== Extra Cheats =====
    // =========================

    function dealMore(
        address _token,
        address _to,
        uint256 _amount
    ) public {
        (, bytes memory rdat) = _token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", _to)
        );
        uint256 balance = abi.decode(rdat, (uint256));

        deal(_token, _to, balance + _amount, true);
    }

    // =========================
    // ===== Extra Asserts =====
    // =========================

    function assertZe(uint256 a) internal {
        if (a != 0) {
            emit log("Error: a == 0 not satisfied [uint]");
            emit log_named_uint("    Value", a);
            fail();
        }
    }

    function assertContains(IntervalUint256 memory a, IntervalUint256 memory b)
        internal
    {
        if (!a.contains(b)) {
            emit log("Error: (b in a) not satisfied [IntervalUint256]");
            if (b.size() == 0) {
                emit log_named_uint("       Expected", b.mean());
            } else {
                emit log_named_uint("  Expected (lo)", b.lo);
                emit log_named_uint("           (hi)", b.hi);
            }
            if (a.size() == 0) {
                emit log_named_uint("         Actual", a.mean());
            } else {
                emit log_named_uint("    Actual (lo)", a.lo);
                emit log_named_uint("           (hi)", a.hi);
            }
            fail();
        }
    }

    function assertEq(IntervalUint256 memory a, uint256 b) internal {
        assertContains(a, IntervalUint256Utils.fromUint256(b));
    }

    function assertEq(uint256 a, IntervalUint256 memory b) internal {
        assertContains(b, IntervalUint256Utils.fromUint256(a));
    }
}

/*
TODO:
- Maybe remove contains syntax
*/
