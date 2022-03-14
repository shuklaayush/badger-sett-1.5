// SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;

import {Vm} from "forge-std/Vm.sol";
import {Multicall3} from "multicall/Multicall3.sol";

import {IntervalUint256, IntervalUint256Utils} from "./IntervalUint256.sol";
import {DSTest2} from "./DSTest2.sol";

contract Snapshot {
    mapping(string => uint256) private values;
    mapping(string => bool) public exists;

    constructor(string[] memory _keys, uint256[] memory _vals) {
        uint256 length = _keys.length;
        for (uint256 i; i < length; ++i) {
            string memory key = _keys[i];
            exists[key] = true;
            values[key] = _vals[i];
        }
    }

    function valOf(string calldata _key) public view returns (uint256 val_) {
        require(exists[_key], "Invalid key");
        val_ = values[_key];
    }
}

contract SnapshotUtils is DSTest2 {
    using IntervalUint256Utils for IntervalUint256;

    /// ===================
    /// ===== Asserts =====
    /// ===================

    function diff(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public view returns (uint256 val_) {
        val_ = _snap1.valOf(_key) - _snap2.valOf(_key);
    }

    function assertEq(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public {
        assertEq(_snap1.valOf(_key), _snap2.valOf(_key));
    }

    function assertAeq(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key,
        uint256 _tol
    ) public {
        assertEq(
            IntervalUint256Utils.fromMeanAndTol(_snap1.valOf(_key), _tol),
            _snap2.valOf(_key)
        );
    }

    function assertAeqRel(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key,
        uint256 _tolBps
    ) public {
        assertEq(
            IntervalUint256Utils.fromMeanAndTolBps(_snap1.valOf(_key), _tolBps),
            _snap2.valOf(_key)
        );
    }

    function assertGt(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public {
        assertGt(_snap1.valOf(_key), _snap2.valOf(_key));
    }

    function assertLt(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public {
        assertLt(_snap1.valOf(_key), _snap2.valOf(_key));
    }

    function assertGe(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public {
        assertGe(_snap1.valOf(_key), _snap2.valOf(_key));
    }

    function assertLe(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key
    ) public {
        assertLe(_snap1.valOf(_key), _snap2.valOf(_key));
    }

    function assertDiff(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key,
        uint256 _diff
    ) public {
        assertEq(_snap1.valOf(_key) - _snap2.valOf(_key), _diff);
    }

    function assertDiff(
        Snapshot _snap1,
        Snapshot _snap2,
        string calldata _key,
        IntervalUint256 memory _diff
    ) public {
        assertEq(_snap1.valOf(_key) - _snap2.valOf(_key), _diff);
    }
}

contract SnapshotManager {
    Vm constant vm_snapshot_manager =
        Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    Multicall3 constant MULTICALL =
        Multicall3(0xcA11bde05977b3631167028862bE2a173976CA11);

    string[] private keys;
    mapping(string => bool) public exists;

    Multicall3.Call[] private calls;

    constructor() {
        if (address(MULTICALL).code.length == 0) {
            vm_snapshot_manager.etch(
                address(MULTICALL),
                type(Multicall3).runtimeCode
            );
        }
    }

    function addCall(
        string calldata _key,
        address _target,
        bytes calldata _callData
    ) public {
        if (!exists[_key]) {
            exists[_key] = true;
            keys.push(_key);
            calls.push(Multicall3.Call(_target, _callData));
        }
    }

    function snap() public returns (Snapshot snap_) {
        (, bytes[] memory rdata) = MULTICALL.aggregate(calls);
        uint256 length = rdata.length;

        uint256[] memory vals = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            vals[i] = abi.decode(rdata[i], (uint256));
        }

        snap_ = new Snapshot(keys, vals);
    }
}

contract SnapshotComparator is SnapshotManager, SnapshotUtils {
    Snapshot sCurr;
    Snapshot sPrev;

    constructor() {}

    function snapPrev() public {
        sPrev = snap();
    }

    function snapCurr() public {
        sCurr = snap();
    }

    function curr(string calldata _key) public view returns (uint256 val_) {
        val_ = sCurr.valOf(_key);
    }

    function prev(string calldata _key) public view returns (uint256 val_) {
        val_ = sPrev.valOf(_key);
    }

    function diff(string calldata _key) public view returns (uint256 val_) {
        val_ = diff(sCurr, sPrev, _key);
    }

    function negDiff(string calldata _key) public view returns (uint256 val_) {
        val_ = diff(sPrev, sCurr, _key);
    }

    function assertEq(string calldata _key) public {
        assertEq(sCurr, sPrev, _key);
    }

    function assertGt(string calldata _key) public {
        assertGt(sCurr, sPrev, _key);
    }

    function assertLt(string calldata _key) public {
        assertLt(sCurr, sPrev, _key);
    }

    function assertGe(string calldata _key) public {
        assertGe(sCurr, sPrev, _key);
    }

    function assertLe(string calldata _key) public {
        assertLe(sCurr, sPrev, _key);
    }

    function assertDiff(string calldata _key, uint256 _diff) public {
        assertDiff(sCurr, sPrev, _key, _diff);
    }

    function assertDiff(string calldata _key, IntervalUint256 memory _diff)
        public
    {
        assertDiff(sCurr, sPrev, _key, _diff);
    }

    function assertNegDiff(string calldata _key, uint256 _diff) public {
        assertDiff(sPrev, sCurr, _key, _diff);
    }

    function assertNegDiff(string calldata _key, IntervalUint256 memory _diff)
        public
    {
        assertDiff(sPrev, sCurr, _key, _diff);
    }
}

/*
TODO:
- Ideally some of this can be a library
- Errors instead of revert string
- log table function
*/
