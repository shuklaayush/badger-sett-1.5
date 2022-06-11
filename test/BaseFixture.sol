// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SnapshotComparator} from "forge-utils/SnapshotUtils.sol";
import {Strings} from "forge-utils/libraries/Strings.sol";
import {TestPlus} from "forge-utils/TestPlus.sol";

import {Vault} from "../src/Vault.sol";
import {Guestlist} from "../src/Guestlist.sol";

import {Config} from "./Config.sol";
import {MockStrategy} from "./mock/MockStrategy.sol";
import {MockToken} from "./mock/MockToken.sol";

contract BaseFixture is TestPlus, Config {
    // ==============
    // ===== Vm =====
    // ==============

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
        // Label
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
            string memory name = string.concat(
                "EMITS[",
                Strings.toString(i),
                "]"
            );
            emitsd[i] = token;
            EMITS_NAMES[i] = name;
            vm.label(token, name);
        }

        // Initialize
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

        // Extra
        dealMore(WANT, address(this), AMOUNT_TO_MINT);

        comparator = new SnapshotComparator();
    }

    // ============================
    // ===== Internal helpers =====
    // ============================

    function addGuestlist() internal {
        Guestlist guestlist = new Guestlist();
        guestlist.initialize(address(vault));

        guestlist.setGuestRoot(bytes32(uint256(1)));
        address[] memory guests = new address[](1);
        bool[] memory invited = new bool[](1);
        guests[0] = address(this);
        invited[0] = true;
        guestlist.setGuests(guests, invited);

        vm.prank(governance);
        vault.setGuestList(address(guestlist));
    }

    // ===========================
    // ===== Deposit Helpers =====
    // ===========================

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
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );
    }

    function postDeposit(uint256 _amount) internal returns (uint256 shares_) {
        uint256 expectedShares = comparator.prev("vault.balance()") > 0
            ? (_amount * comparator.prev("vault.totalSupply()")) /
                comparator.prev("vault.balance()")
            : _amount;

        assertEq(comparator.negDiff("want.balanceOf(from)"), _amount);
        assertEq(comparator.diff("want.balanceOf(vault)"), _amount);
        assertEq(comparator.diff("vault.balanceOf(to)"), expectedShares);
        // PPS might increase slightly due to rounding errors
        assertGe(comparator.diff("vault.getPricePerFullShare()"), 0);

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

    // ========================
    // ===== Earn Helpers =====
    // ========================

    function prepareEarn() internal {
        comparator.addCall(
            "want.balanceOf(vault)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );
        comparator.addCall(
            "strategy.balanceOfPool()",
            address(strategy),
            abi.encodeWithSignature("balanceOfPool()")
        );
    }

    function postEarn(uint256 _amount) internal {
        assertEq(comparator.negDiff("want.balanceOf(vault)"), _amount);

        // TODO: Maybe relax this for loss making strategies?
        assertEq(comparator.diff("strategy.balanceOfPool()"), _amount);
    }

    function earnChecked() internal {
        uint256 expectedEarn = (IERC20(WANT).balanceOf(address(vault)) *
            vault.toEarnBps()) / MAX_BPS;
        prepareEarn();

        comparator.snapPrev();

        vm.prank(keeper);
        vault.earn();

        comparator.snapCurr();

        postEarn(expectedEarn);
    }

    // ============================
    // ===== Withdraw Helpers =====
    // ============================

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
            "want.balanceOf(strategy)",
            WANT,
            abi.encodeWithSignature("balanceOf(address)", address(strategy))
        );
        comparator.addCall(
            "strategy.balanceOfPool()",
            address(strategy),
            abi.encodeWithSignature("balanceOfPool()")
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
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );
    }

    function postWithdraw(uint256 _shares) internal returns (uint256 amount_) {
        uint256 amountZeroFee = (_shares * comparator.prev("vault.balance()")) /
            comparator.prev("vault.totalSupply()");

        uint256 withdrawalFee = (amountZeroFee * WITHDRAWAL_FEE) / MAX_BPS;
        uint256 withdrawalFeeInShares = (withdrawalFee *
            comparator.prev("vault.totalSupply()")) /
            comparator.prev("vault.balance()");

        uint256 amount = amountZeroFee - withdrawalFee;

        assertEq(comparator.negDiff("vault.balanceOf(from)"), _shares);
        assertEq(comparator.diff("want.balanceOf(from)"), amount);
        assertEq(
            comparator.diff("vault.balanceOf(treasury)"),
            withdrawalFeeInShares
        );
        // PPS might increase slightly due to rounding errors
        assertGe(comparator.diff("vault.getPricePerFullShare()"), 0);

        // TODO: Assumes no loss
        if (amountZeroFee <= comparator.prev("want.balanceOf(vault)")) {
            assertEq(comparator.negDiff("want.balanceOf(vault)"), amount);
        } else {
            uint256 amountFromStrategy = amountZeroFee -
                comparator.prev("want.balanceOf(vault)");

            assertEq(comparator.curr("want.balanceOf(vault)"), withdrawalFee);

            if (
                amountFromStrategy <=
                comparator.prev("want.balanceOf(strategy)")
            ) {
                assertEq(
                    comparator.negDiff("want.balanceOf(strategy)"),
                    amountFromStrategy
                );
            } else {
                uint256 amountFromStrategyPool = amountFromStrategy -
                    comparator.prev("want.balanceOf(strategy)");

                assertEq(comparator.curr("want.balanceOf(strategy)"), 0);
                assertEq(
                    comparator.negDiff("strategy.balanceOfPool()"),
                    amountFromStrategyPool
                );
            }
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

    function prepareWithdrawToVault() internal {
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
    }

    function postWithdrawToVault() internal {
        assertEq(comparator.curr("strategy.balanceOf()"), 0);
        // TODO: Maybe relax this for loss making strategies?
        assertEq(
            comparator.diff("want.balanceOf(vault)"),
            comparator.prev("strategy.balanceOf()")
        );
    }

    function withdrawToVaultChecked() internal {
        prepareWithdrawToVault();

        comparator.snapPrev();

        vm.prank(governance);
        vault.withdrawToVault();

        comparator.snapCurr();

        postWithdrawToVault();
    }

    // ===========================
    // ===== Harvest Helpers =====
    // ===========================

    function prepareReportAdditionalToken(address _token, string memory _name)
        internal
    {
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

    function prepareEventsReportAdditionalTokenExact(
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

    function postReportAdditionalTokenExact(
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

    function reportAdditionalTokenCheckedExact(
        address _token,
        uint256 _amount,
        string memory _name
    ) internal {
        prepareReportAdditionalToken(_token, _name);

        comparator.snapPrev();

        dealMore(_token, address(vault), _amount);

        prepareEventsReportAdditionalTokenExact(_token, _amount);
        vm.prank(address(strategy));
        vault.reportAdditionalToken(_token);

        comparator.snapCurr();

        postReportAdditionalTokenExact(_name, _amount);
    }

    function emitNonProtectedTokenChecked(
        address _token,
        uint256 _amount,
        string memory _name
    ) internal {
        prepareReportAdditionalToken(_token, _name);

        comparator.snapPrev();

        dealMore(_token, address(strategy), _amount);

        prepareEventsReportAdditionalTokenExact(_token, _amount);
        vm.prank(governance);
        vault.emitNonProtectedToken(_token);

        comparator.snapCurr();

        postReportAdditionalTokenExact(_name, _amount);
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
        comparator.addCall(
            "vault.getPricePerFullShare()",
            address(vault),
            abi.encodeWithSignature("getPricePerFullShare()")
        );
    }

    function prepareEventsReportHarvestExact(uint256 _amount) internal {
        vm.expectEmit(true, true, false, true);
        emit Harvested(WANT, _amount, block.number, block.timestamp);
    }

    function postReportHarvestExact(
        uint256 _amount,
        uint256 _timeSinceLastHarvest
    ) internal {
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
        assertGe(comparator.diff("vault.getPricePerFullShare()"), 0);
    }

    function reportHarvestCheckedExact(
        uint256 _amount,
        uint256 _timeSinceLastHarvest
    ) internal {
        prepareReportHarvest();

        comparator.snapPrev();

        dealMore(WANT, address(vault), _amount);

        prepareEventsReportHarvestExact(_amount);
        vm.prank(address(strategy));
        vault.reportHarvest(_amount);

        comparator.snapCurr();

        postReportHarvestExact(_amount, _timeSinceLastHarvest);
    }

    function reportHarvestCheckedExact(uint256 _amount) internal {
        reportHarvestCheckedExact(_amount, 0);
    }

    // TODO: Rename this harvestCheckedExact and add another where harvest amounts are unknown
    function harvestCheckedExact(
        uint256 _wantAmount,
        uint256[] memory _emitAmounts,
        uint256 _timeSinceLastHarvest
    ) internal {
        prepareReportHarvest();
        for (uint256 i; i < NUM_EMITS; ++i) {
            prepareReportAdditionalToken(EMITS[i], EMITS_NAMES[i]);
        }

        comparator.snapPrev();

        dealMore(WANT, address(strategy), _wantAmount);
        strategy.setHarvestAmount(_wantAmount);

        for (uint256 i; i < NUM_EMITS; ++i) {
            dealMore(EMITS[i], address(strategy), _emitAmounts[i]);
        }

        prepareEventsReportHarvestExact(_wantAmount);
        for (uint256 i; i < NUM_EMITS; ++i) {
            prepareEventsReportAdditionalTokenExact(EMITS[i], _emitAmounts[i]);
        }
        vm.prank(keeper);
        MockStrategy.TokenAmount[] memory harvestedTokenAmounts = strategy
            .harvest();

        comparator.snapCurr();

        assertEq(harvestedTokenAmounts.length, NUM_EMITS + 1);

        assertEq(harvestedTokenAmounts[0].token, WANT);
        assertEq(harvestedTokenAmounts[0].amount, _wantAmount);

        postReportHarvestExact(_wantAmount, _timeSinceLastHarvest);
        for (uint256 i; i < NUM_EMITS; ++i) {
            assertEq(harvestedTokenAmounts[i + 1].token, EMITS[i]);
            assertEq(harvestedTokenAmounts[i + 1].amount, _emitAmounts[i]);

            postReportAdditionalTokenExact(EMITS_NAMES[i], _emitAmounts[i]);
        }
    }

    function harvestCheckedExact(
        uint256 _wantAmount,
        uint256[] memory _emitAmounts
    ) internal {
        harvestCheckedExact(_wantAmount, _emitAmounts, 0);
    }
}

/*
TODO:
- Tend
- vm.label with .name() instead?
- fixed point math?
- emitNonProtectedToken ==> reportAdditionTokenManual?
- Maybe move minting outside checked function?
- Rename guestlist, make it a modifier? Only on external functions
- Strategy reports loss and assert(loss < some value) instead of IntervalUint
*/
