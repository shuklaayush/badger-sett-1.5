// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseFixture} from "./BaseFixture.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

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
        harvestChecked(1e18, emitAmounts, 1 days);

        withdrawAllChecked();
    }

    /// ============================
    /// ===== Internal helpers =====
    /// ============================
}
