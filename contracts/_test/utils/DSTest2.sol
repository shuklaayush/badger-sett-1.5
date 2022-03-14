// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {IntervalUint256, IntervalUint256Utils} from "./IntervalUint256.sol";

contract DSTest2 is DSTestPlus {
    using IntervalUint256Utils for IntervalUint256;

    function assertContains(IntervalUint256 memory a, IntervalUint256 memory b)
        internal
    {
        if (!a.contains(b)) {
            emit log("Error: (b in a) not satisfied [IntervalUint256]");
            emit log_named_uint("  Expected", b.mean());
            if (b.size() > 0) {
                emit log_named_uint("        +-", b.size() / 2);
            }
            emit log_named_uint("    Actual", a.mean());
            if (a.size() > 0) {
                emit log_named_uint("        +-", a.size() / 2);
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
