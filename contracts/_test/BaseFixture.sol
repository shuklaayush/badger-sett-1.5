// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Config} from "./Config.sol";
import {Utils} from "./utils/Utils.sol";
import {IntervalUint256, IntervalUint256Utils} from "./utils/IntervalUint256.sol";
import {DSTest2} from "./utils/DSTest2.sol";
import {ERC20Utils} from "./utils/ERC20Utils.sol";
import {SnapshotComparator} from "./utils/SnapshotUtils.sol";
import {Vault} from "../Vault.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract BaseFixture is DSTest2, stdCheats, Config, Utils {
    using IntervalUint256Utils for IntervalUint256;

    // ==============
    // ===== Vm =====
    // ==============

    Vm constant vm = Vm(HEVM_ADDRESS);

    ERC20Utils immutable erc20utils = new ERC20Utils();
    SnapshotComparator comparator;

    uint256 internal immutable NUM_EMITS = EMITS.length;
    string[] internal EMITS_NAMES;

    // =====================
    // ===== Constants =====
    // =====================

    uint256 constant MAX_BPS = 10_000;
    uint256 constant SECS_IN_YEAR = 31_556_952;
    uint256 constant AMOUNT_TO_MINT = 10e18;

    // ==================
    // ===== Actors =====
    // ==================

    address immutable governance = getAddress("governance");
    address immutable strategist = getAddress("strategist");
    address immutable guardian = getAddress("guardian");
    address immutable keeper = getAddress("keeper");
    address immutable treasury = getAddress("treasury");
    address immutable badgerTree = getAddress("badgerTree");

    address immutable rando = getAddress("rando");

    // =================
    // ===== State =====
    // =================

    Vault vault = new Vault();
    MockStrategy strategy = new MockStrategy();

    // ==================
    // ===== Events =====
    // ==================

    event SetStrategy(address indexed newStrategy);

    event Harvested(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event PerformanceFeeGovernance(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    event PerformanceFeeStrategist(
        address indexed destination,
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    // ==================
    // ===== Set up =====
    // ==================

    function setUp() public virtual {
        // =================
        // ===== Label =====
        // =================

        vm.label(address(this), "this");

        vm.label(governance, "governance");
        vm.label(keeper, "keeper");
        vm.label(guardian, "guardian");
        vm.label(treasury, "treasury");
        vm.label(strategist, "strategist");
        vm.label(badgerTree, "badgerTree");

        vm.label(rando, "rando");

        vm.label(address(vault), "vault");
        vm.label(address(strategy), "strategy");

        vm.label(WANT, "want");

        address[] memory emitsd = new address[](NUM_EMITS);
        EMITS_NAMES = new string[](NUM_EMITS);
        for (uint256 i; i < NUM_EMITS; ++i) {
            address token = EMITS[i];
            string memory name = string.concat("EMITS[", toString(i), "]");
            emitsd[i] = token;
            EMITS_NAMES[i] = name;
            vm.label(token, name);
        }

        // ======================
        // ===== Initialize =====
        // ======================

        vault.initialize(
            WANT,
            governance,
            keeper,
            guardian,
            treasury,
            strategist,
            badgerTree,
            "",
            "",
            [
                PERFORMANCE_FEE_GOVERNANCE,
                PERFORMANCE_FEE_STRATEGIST,
                WITHDRAWAL_FEE,
                MANAGEMENT_FEE
            ]
        );

        strategy.initialize(address(vault), emitsd);

        vm.prank(governance);
        vault.setStrategy(address(strategy));

        erc20utils.forceMint(WANT, AMOUNT_TO_MINT);

        comparator = new SnapshotComparator();
    }

    /// ============================
    /// ===== Internal helpers =====
    /// ============================

    function prepareDepositFor(address _from, address _to) internal {
        comparator.addCall(
            "want.balanceOf(from)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "vault.balanceOf(to)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", _to)
        );
        comparator.addCall(
            "vault.balance()",
            address(vault),
            abi.encodeWithSignature("balance()")
        );
        comparator.addCall(
            "vault.totalSupply()",
            address(vault),
            abi.encodeWithSignature("totalSupply()")
        );
        // TODO: this?
        // comparator.addCall(
        //     "vault.getPricePerFullShare()",
        //     address(vault),
        //     abi.encodeWithSignature("getPricePerFullShare()")
        // );
    }

    function postDeposit(uint256 _amount) internal returns (uint256 shares_) {
        uint256 expectedShares = comparator.prev("vault.balance()") > 0
            ? (_amount * comparator.prev("vault.totalSupply()")) /
                comparator.prev("vault.balance()")
            : _amount;

        assertEq(comparator.negDiff("want.balanceOf(from)"), _amount);
        assertEq(comparator.diff("want.balanceOf(vault)"), _amount);
        assertEq(comparator.diff("vault.balanceOf(to)"), expectedShares);

        shares_ = comparator.diff("vault.balanceOf(to)");
    }

    function depositCheckedFrom(address _from, uint256 _amount)
        internal
        returns (uint256 shares_)
    {
        prepareDepositFor(_from, _from);

        comparator.snapPrev();

        vm.startPrank(_from, _from);
        IERC20(WANT).approve(address(vault), _amount);
        vault.deposit(_amount);
        vm.stopPrank();

        comparator.snapCurr();

        shares_ = postDeposit(_amount);
    }

    function depositChecked(uint256 _amount)
        internal
        returns (uint256 shares_)
    {
        shares_ = depositCheckedFrom(address(this), _amount);
    }

    function depositForCheckedFrom(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256 shares_) {
        prepareDepositFor(_from, _to);

        comparator.snapPrev();

        vm.startPrank(_from, _from);
        IERC20(WANT).approve(address(vault), _amount);
        vault.depositFor(_to, _amount);
        vm.stopPrank();

        comparator.snapCurr();

        shares_ = postDeposit(_amount);
    }

    function depositForChecked(uint256 _amount, address _to)
        internal
        returns (uint256 shares_)
    {
        shares_ = depositForCheckedFrom(address(this), _to, _amount);
    }

    function depositAllCheckedFrom(address _from)
        internal
        returns (uint256 shares_)
    {
        uint256 amount = IERC20(WANT).balanceOf(_from);
        prepareDepositFor(_from, _from);

        comparator.snapPrev();

        vm.startPrank(_from, _from);
        IERC20(WANT).approve(address(vault), amount);
        vault.depositAll();
        vm.stopPrank();

        comparator.snapCurr();

        shares_ = postDeposit(amount);
    }

    function depositAllChecked() internal returns (uint256 shares_) {
        shares_ = depositAllCheckedFrom(address(this));
    }

    function earnChecked() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );

        uint256 expectedEarn = (IERC20(WANT).balanceOf(address(vault)) *
            vault.toEarnBps()) / MAX_BPS;

        comparator.snapPrev();

        vm.prank(keeper);
        vault.earn();

        comparator.snapCurr();

        assertEq(comparator.negDiff("want.balanceOf(vault)"), expectedEarn);

        // TODO: Maybe relax this for loss making strategies?
        assertEq(comparator.diff("strategy.balanceOf()"), expectedEarn);
    }

    function prepareWithdraw(address _from) internal {
        comparator.addCall(
            "vault.balanceOf(from)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "vault.balanceOf(treasury)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            "want.balanceOf(from)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", _from)
        );
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );
        comparator.addCall(
            "vault.balance()",
            address(vault),
            abi.encodeWithSignature("balance()")
        );
        comparator.addCall(
            "vault.totalSupply()",
            address(vault),
            abi.encodeWithSignature("totalSupply()")
        );
        // comparator.addCall(
        //     "vault.getPricePerFullShare()",
        //     address(vault),
        //     abi.encodeWithSignature("getPricePerFullShare()")
        // );
    }

    function postWithdraw(uint256 _shares) internal returns (uint256 amount_) {
        uint256 amountZeroFee = (_shares * comparator.prev("vault.balance()")) /
            comparator.prev("vault.totalSupply()");

        assertEq(comparator.negDiff("vault.balanceOf(from)"), _shares);

        if (amountZeroFee <= comparator.prev("want.balanceOf(vault)")) {
            uint256 withdrawalFee = (amountZeroFee * WITHDRAWAL_FEE) / MAX_BPS;

            uint256 withdrawalFeeInShares = (withdrawalFee *
                comparator.prev("vault.totalSupply()")) /
                comparator.prev("vault.balance()");

            uint256 amount = amountZeroFee - withdrawalFee;

            assertEq(comparator.negDiff("want.balanceOf(vault)"), amount);
            assertEq(comparator.diff("want.balanceOf(from)"), amount);
            assertEq(
                comparator.diff("vault.balanceOf(treasury)"),
                withdrawalFeeInShares
            );
        } else {
            // TODO: Probably doesn't make sense since loss isn't handled properly in strat
            IntervalUint256 memory amountFromStrategyInterval = IntervalUint256Utils
                .fromMaxAndTolBps(
                    amountZeroFee - comparator.prev("want.balanceOf(vault)"),
                    10 // TODO: No magic
                );

            IntervalUint256
                memory amountZeroFeeInterval = amountFromStrategyInterval.add(
                    comparator.prev("want.balanceOf(vault)")
                );

            IntervalUint256 memory withdrawalFee = amountZeroFeeInterval
                .mul(WITHDRAWAL_FEE)
                .div(MAX_BPS);

            IntervalUint256 memory withdrawalFeeInShares = withdrawalFee
                .mul(comparator.prev("vault.totalSupply()"))
                .div(comparator.prev("vault.balance()"));

            assertEq(comparator.curr("want.balanceOf(vault)"), withdrawalFee);
            assertEq(
                comparator.diff("want.balanceOf(from)"),
                amountZeroFeeInterval.sub(withdrawalFee, true)
            );
            assertEq(
                comparator.diff("vault.balanceOf(treasury)"),
                withdrawalFeeInShares
            );
            assertEq(
                comparator.negDiff("strategy.balanceOf()"),
                amountFromStrategyInterval
            );
        }

        amount_ = comparator.diff("want.balanceOf(from)");
    }

    function withdrawCheckedFrom(address _from, uint256 _shares)
        internal
        returns (uint256 amount_)
    {
        prepareWithdraw(_from);

        comparator.snapPrev();

        vm.prank(_from, _from);
        vault.withdraw(_shares);

        comparator.snapCurr();

        amount_ = postWithdraw(_shares);
    }

    function withdrawChecked(uint256 _shares)
        internal
        returns (uint256 amount_)
    {
        amount_ = withdrawCheckedFrom(address(this), _shares);
    }

    function withdrawAllCheckedFrom(address _from)
        internal
        returns (uint256 amount_)
    {
        prepareWithdraw(_from);

        comparator.snapPrev();

        uint256 shares = vault.balanceOf(_from);
        vault.withdrawAll();

        comparator.snapCurr();

        amount_ = postWithdraw(shares);
    }

    function withdrawAllChecked() internal returns (uint256 amount_) {
        amount_ = withdrawAllCheckedFrom(address(this));
    }

    function withdrawToVaultChecked() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOf()",
            address(strategy),
            abi.encodeWithSignature("balanceOf()")
        );

        comparator.snapPrev();

        vm.prank(governance);
        vault.withdrawToVault();

        comparator.snapCurr();

        assertEq(comparator.curr("strategy.balanceOf()"), 0);
        // TODO: Maybe relax this for loss making strategies?
        assertEq(
            comparator.diff("want.balanceOf(vault)"),
            comparator.prev("strategy.balanceOf()")
        );
    }

    function prepareReportAdditionalTokenChecked(
        address _token,
        string memory _name
    ) internal {
        comparator.addCall(
            string.concat(_name, ".balanceOf(treasury)"),
            _token,
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            string.concat(_name, ".balanceOf(strategist)"),
            _token,
            abi.encodeWithSignature("balanceOf(address)", strategist)
        );
        comparator.addCall(
            string.concat(_name, ".balanceOf(badgerTree)"),
            _token,
            abi.encodeWithSignature("balanceOf(address)", badgerTree)
        );
        comparator.addCall(
            string.concat("vault.lastAdditionalTokenAmount(", _name, ")"),
            address(vault),
            abi.encodeWithSignature(
                "lastAdditionalTokenAmount(address)",
                _token
            )
        );
        comparator.addCall(
            string.concat("vault.additionalTokensEarned(", _name, ")"),
            address(vault),
            abi.encodeWithSignature("additionalTokensEarned(address)", _token)
        );
    }

    function prepareEventsReportAdditionalTokenChecked(
        address _token,
        uint256 _amount
    ) internal {
        uint256 governancePerformanceFee = (_amount *
            PERFORMANCE_FEE_GOVERNANCE) / MAX_BPS;
        uint256 strategistPerformanceFee = (_amount *
            PERFORMANCE_FEE_STRATEGIST) / MAX_BPS;

        vm.expectEmit(true, true, false, true);
        emit TreeDistribution(
            _token,
            _amount - governancePerformanceFee - strategistPerformanceFee,
            block.number,
            block.timestamp
        );
    }

    function postReportAdditionalTokenChecked(
        string memory _name,
        uint256 _amount
    ) internal {
        uint256 governancePerformanceFee = (_amount *
            PERFORMANCE_FEE_GOVERNANCE) / MAX_BPS;
        uint256 strategistPerformanceFee = (_amount *
            PERFORMANCE_FEE_STRATEGIST) / MAX_BPS;

        assertEq(
            comparator.curr(
                string.concat("vault.lastAdditionalTokenAmount(", _name, ")")
            ),
            _amount
        );
        assertEq(
            comparator.diff(
                string.concat("vault.additionalTokensEarned(", _name, ")")
            ),
            _amount
        );
        assertEq(
            comparator.diff(string.concat(_name, ".balanceOf(treasury)")),
            governancePerformanceFee
        );
        assertEq(
            comparator.diff(string.concat(_name, ".balanceOf(strategist)")),
            strategistPerformanceFee
        );
        assertEq(
            comparator.diff(string.concat(_name, ".balanceOf(badgerTree)")),
            _amount - governancePerformanceFee - strategistPerformanceFee
        );
    }

    function reportAdditionalTokenChecked(
        address _token,
        uint256 _amount,
        string memory _name
    ) internal {
        prepareReportAdditionalTokenChecked(_token, _name);

        comparator.snapPrev();

        erc20utils.forceMintTo(address(vault), _token, _amount);

        prepareEventsReportAdditionalTokenChecked(_token, _amount);
        vm.prank(address(strategy));
        vault.reportAdditionalToken(_token);

        comparator.snapCurr();

        postReportAdditionalTokenChecked(_name, _amount);
    }

    function prepareReportHarvest() internal {
        comparator.addCall(
            "vault.balance()",
            address(vault),
            abi.encodeWithSignature("balance()")
        );
        comparator.addCall(
            "vault.balanceOf(treasury)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", treasury)
        );
        comparator.addCall(
            "vault.balanceOf(strategist)",
            address(vault),
            abi.encodeWithSignature("balanceOf(address)", strategist)
        );
        comparator.addCall(
            "vault.lastHarvestAmount()",
            address(vault),
            abi.encodeWithSignature("lastHarvestAmount()")
        );
        comparator.addCall(
            "vault.assetsAtLastHarvest()",
            address(vault),
            abi.encodeWithSignature("assetsAtLastHarvest()")
        );
        comparator.addCall(
            "vault.lastHarvestedAt()",
            address(vault),
            abi.encodeWithSignature("lastHarvestedAt()")
        );
        comparator.addCall(
            "vault.lifeTimeEarned()",
            address(vault),
            abi.encodeWithSignature("lifeTimeEarned()")
        );
        comparator.addCall(
            "vault.totalSupply()",
            address(vault),
            abi.encodeWithSignature("totalSupply()")
        );
        // TODO: Add?
        // comparator.addCall(
        //     "vault.getPricePerFullShare()",
        //     address(vault),
        //     abi.encodeWithSignature("getPricePerFullShare()")
        // );
        //  comparator.addCall(
        //     "strategy.balanceOf()",
        //     address(strategy),
        //     abi.encodeWithSignature("balanceOf()")
        // );
    }

    function prepareEventsHarvestChecked(uint256 _amount) internal {
        vm.expectEmit(true, true, false, true);
        emit Harvested(WANT, _amount, block.number, block.timestamp);
    }

    function postReportHarvest(uint256 _amount, uint256 _timeSinceLastHarvest)
        internal
    {
        uint256 strategistPerformanceFee = (_amount *
            PERFORMANCE_FEE_STRATEGIST) / MAX_BPS;
        uint256 governancePerformanceFee = (_amount *
            PERFORMANCE_FEE_GOVERNANCE) / MAX_BPS;
        uint256 managementFee = (comparator.prev("vault.balance()") *
            _timeSinceLastHarvest *
            MANAGEMENT_FEE) /
            MAX_BPS /
            SECS_IN_YEAR;
        uint256 governanceFee = managementFee + governancePerformanceFee;

        assertEq(comparator.diff("vault.balance()"), _amount);

        assertEq(
            comparator.diff("vault.balanceOf(treasury)"),
            (governanceFee * comparator.curr("vault.totalSupply()")) /
                comparator.curr("vault.balance()")
        );
        assertEq(
            comparator.diff("vault.balanceOf(strategist)"),
            (strategistPerformanceFee *
                comparator.curr("vault.totalSupply()")) /
                comparator.curr("vault.balance()")
        );

        // TODO: Needs to be handled separately
        // if (comparator.prev("vault.balance()") == 0) {
        //     assertEq(
        //         comparator.diff("vault.balanceOf(treasury)"),
        //         governanceFee
        //     );
        //     assertEq(
        //         comparator.diff("vault.balanceOf(strategist)"),
        //         strategistPerformanceFee
        //     );
        // }

        assertEq(comparator.curr("vault.lastHarvestAmount()"), _amount);
        assertEq(
            comparator.curr("vault.assetsAtLastHarvest()"),
            comparator.prev("vault.balance()")
        );
        assertEq(comparator.curr("vault.lastHarvestedAt()"), block.timestamp);
        assertEq(comparator.diff("vault.lifeTimeEarned()"), _amount);

        // TODO: Add these?
        // assertZe(comparator.diff("strategy.balanceOf()"));
    }

    function reportHarvestChecked(
        uint256 _amount,
        uint256 _timeSinceLastHarvest
    ) internal {
        prepareReportHarvest();

        comparator.snapPrev();

        erc20utils.forceMintTo(address(vault), WANT, _amount);

        prepareEventsHarvestChecked(_amount);
        vm.prank(address(strategy));
        vault.reportHarvest(_amount);

        comparator.snapCurr();

        postReportHarvest(_amount, _timeSinceLastHarvest);
    }

    function reportHarvestChecked(uint256 _amount) internal {
        reportHarvestChecked(_amount, 0);
    }

    function harvestChecked(
        uint256 _wantAmount,
        uint256[] memory _emitAmounts,
        uint256 _timeSinceLastHarvest
    ) internal {
        prepareReportHarvest();
        for (uint256 i; i < NUM_EMITS; ++i) {
            prepareReportAdditionalTokenChecked(EMITS[i], EMITS_NAMES[i]);
        }

        comparator.snapPrev();

        erc20utils.forceMintTo(address(strategy), WANT, _wantAmount);
        strategy.setHarvestAmount(_wantAmount);

        for (uint256 i; i < NUM_EMITS; ++i) {
            erc20utils.forceMintTo(
                address(strategy),
                EMITS[i],
                _emitAmounts[i]
            );
        }

        prepareEventsHarvestChecked(_wantAmount);
        for (uint256 i; i < NUM_EMITS; ++i) {
            prepareEventsReportAdditionalTokenChecked(
                EMITS[i],
                _emitAmounts[i]
            );
        }
        vm.prank(keeper);
        strategy.harvest();
        // TODO: Return value?

        comparator.snapCurr();

        // assertEq(harvested, 0);

        postReportHarvest(_wantAmount, _timeSinceLastHarvest);
        for (uint256 i; i < NUM_EMITS; ++i) {
            postReportAdditionalTokenChecked(EMITS_NAMES[i], _emitAmounts[i]);
        }
    }

    function harvestChecked(uint256 _wantAmount, uint256[] memory _emitAmounts)
        internal
    {
        harvestChecked(_wantAmount, _emitAmounts, 0);
    }
}

/*
TODO:
- add a demo staking pool for `balanceOfPool` tests
- vm.label with .name() instead?
- fixed point math?
*/
