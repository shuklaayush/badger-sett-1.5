// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {BaseFixture} from "./BaseFixture.sol";

contract IntegrationTest is BaseFixture {
    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public override {
        BaseFixture.setUp();
    }

    // ========================
    // ===== Harvest flow =====
    // ========================

    function testHarvestFlow() public {
        depositAllChecked();
        earnChecked();

        skip(1 days);

        uint256[] memory emitAmounts = new uint256[](NUM_EMITS);
        for (uint256 i; i < NUM_EMITS; ++i) {
            emitAmounts[i] = (i + 2) * 10**18;
        }
        harvestCheckedExact(1e18, emitAmounts, 1 days);

        withdrawAllChecked();
    }

    function testHarvestFlowWithdrawTwice() public {
        uint256 shares = depositAllChecked();
        earnChecked();

        skip(1 days);

        uint256[] memory emitAmounts = new uint256[](NUM_EMITS);
        for (uint256 i; i < NUM_EMITS; ++i) {
            emitAmounts[i] = (i + 2) * 10**18;
        }
        harvestCheckedExact(1e18, emitAmounts, 1 days);
        withdrawChecked(shares / 2);

        skip(2 days);

        harvestCheckedExact(1e18, emitAmounts, 2 days);
        withdrawAllChecked();
    }

    function testMigrate() public {
        depositAllChecked();
        skip(1 hours);

        earnChecked();
        skip(2 days);

        uint256[] memory emitAmounts = new uint256[](NUM_EMITS);
        for (uint256 i; i < NUM_EMITS; ++i) {
            emitAmounts[i] = (i + 2) * 10**18;
        }
        harvestCheckedExact(1e18, emitAmounts, 2 days + 1 hours);
        skip(1 days);

        withdrawToVaultChecked();
    }

    // ============================
    // ===== Internal helpers =====
    // ============================
}
