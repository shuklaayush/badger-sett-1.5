// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;

struct ApproxUint256 {
    uint256 val;
    uint256 tol;
}

library ApproxUint256Utils {
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function add(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        return ApproxUint256(a.val + b, a.tol);
    }

    function add(ApproxUint256 memory a, ApproxUint256 memory b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        return ApproxUint256(a.val + b.val, a.tol + b.tol);
    }

    function sub(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        return ApproxUint256(a.val - b, a.tol);
    }

    function sub(
        ApproxUint256 memory a,
        ApproxUint256 memory b,
        bool _dependent
    ) internal pure returns (ApproxUint256 memory) {
        return
            ApproxUint256(
                a.val - b.val,
                _dependent ? absDiff(a.tol, b.tol) : a.tol + b.tol
            );
    }

    function mul(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        return ApproxUint256(a.val * b, a.tol * b);
    }

    function mul(ApproxUint256 memory a, ApproxUint256 memory b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        // Ignoring a.tol * b.tol term
        return ApproxUint256(a.val * b.val, a.val * b.tol + b.val * a.tol);
    }

    function div(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (ApproxUint256 memory)
    {
        return ApproxUint256(a.val / b, a.tol / b);
    }

    function div(
        ApproxUint256 memory a,
        ApproxUint256 memory b,
        bool _dependent
    ) internal pure returns (ApproxUint256 memory) {
        // Ignoring a.tol * b.tol term
        return
            ApproxUint256(
                a.val / b.val,
                (
                    _dependent
                        ? absDiff(a.val * b.tol, b.val * a.tol)
                        : (a.val * b.tol + b.val * a.tol)
                ) / (b.val * b.val)
            );
    }

    function eq(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (bool)
    {
        return a.val > b ? a.val - b < a.tol : b - a.val < a.tol;
    }

    function eq(ApproxUint256 memory a, ApproxUint256 memory b)
        internal
        pure
        returns (bool)
    {
        return
            a.val > b.val
                ? a.val - b.val < a.tol + b.tol
                : b.val - a.val < a.tol + b.tol;
    }

    function lt(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (bool)
    {
        return a.val + a.tol < b;
    }

    function le(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (bool)
    {
        return a.val + a.tol <= b;
    }

    function gt(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (bool)
    {
        return a.val - a.tol > b;
    }

    function ge(ApproxUint256 memory a, uint256 b)
        internal
        pure
        returns (bool)
    {
        return a.val - a.tol >= b;
    }
}
