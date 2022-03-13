// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ApproxUint256, ApproxUint256Utils} from "./ApproxUint256.sol";

contract DSTest2 is DSTestPlus {
    using ApproxUint256Utils for ApproxUint256;

    function ApproxUint256RelBps(uint256 _val, uint256 _relBps)
        internal
        pure
        returns (ApproxUint256 memory out_)
    {
        out_ = ApproxUint256(_val, (_val * _relBps) / 10_000);
    }

    function assertEq(ApproxUint256 memory a, ApproxUint256 memory b) internal {
        if (!a.eq(b)) {
            emit log("Error: a == b not satisfied [ApproxUint256]");
            emit log_named_uint("  Expected", b.val);
            emit log_named_uint("          +-", b.tol);
            emit log_named_uint("    Actual", a.val);
            emit log_named_uint("          +-", a.tol);
            fail();
        }
    }

    function assertEq(ApproxUint256 memory a, uint256 b) internal {
        assertEq(a, ApproxUint256(b, 0));
    }

    function assertEq(uint256 a, ApproxUint256 memory b) internal {
        assertEq(ApproxUint256(a, 0), b);
    }
}
