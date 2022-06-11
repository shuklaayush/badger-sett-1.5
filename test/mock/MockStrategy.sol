// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {BaseStrategy} from "../../src/BaseStrategy.sol";
import {MockStaker} from "./MockStaker.sol";

contract MockStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public reward;

    uint256 private lossBps;
    uint256 private harvestAmount;

    MockStaker private staker;

    function initialize(address _vault, address[] calldata _tokenConfig)
        public
        initializer
    {
        __BaseStrategy_init(_vault);

        reward = _tokenConfig[0];
        staker = new MockStaker();

        // TODO: Maybe move approvals to a default function?
        IERC20Upgradeable(want).safeApprove(address(staker), type(uint256).max);
    }

    function getName() external pure override returns (string memory) {
        return "MockStrategy";
    }

    function getProtectedTokens()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want;
        protectedTokens[1] = reward;
        return protectedTokens;
    }

    function _isTendable() internal pure override returns (bool) {
        return true;
    }

    function setLossBps(uint256 _lossBps) public {
        lossBps = _lossBps;
    }

    function setHarvestAmount(uint256 _amount) public {
        harvestAmount = _amount;
    }

    function _deposit(uint256 _amount) internal override {
        staker.stake(want, _amount);
    }

    function _withdrawAll() internal override {
        staker.unstake(want, balanceOfPool());
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        // TODO: Move to base, will strategies ever have idle want?
        //       Locker can have idle want if someone kicks after expiry
        uint256 wantBalance = balanceOfWant();
        if (wantBalance < _amount) {
            uint256 toWithdraw = _amount - wantBalance;
            uint256 poolBalance = balanceOfPool();
            if (poolBalance < toWithdraw) {
                staker.unstake(want, poolBalance);
            } else {
                staker.unstake(want, toWithdraw);
            }
        }

        uint256 amount = MathUpgradeable.min(_amount, balanceOfWant());

        uint256 loss = (amount * lossBps) / MAX_BPS;
        IERC20Upgradeable(want).transfer(address(0xdEaD), loss);

        return amount - loss;
    }

    function _harvest()
        internal
        override
        returns (TokenAmount[] memory harvested)
    {
        uint256 harvestRewardAmount = IERC20Upgradeable(reward).balanceOf(
            address(this)
        );

        _reportToVault(harvestAmount);
        if (harvestRewardAmount > 0) {
            _processExtraToken(reward, harvestRewardAmount);
        }

        harvested = new TokenAmount[](2);
        harvested[0] = TokenAmount(want, harvestAmount);
        harvested[1] = TokenAmount(reward, harvestRewardAmount);
    }

    function _tend()
        internal
        view
        override
        returns (TokenAmount[] memory tended)
    {
        // Nothing tended
        tended = new TokenAmount[](2);
        tended[0] = TokenAmount(want, 0);
        tended[1] = TokenAmount(reward, 0);
        return tended;
    }

    function balanceOfPool() public view override returns (uint256) {
        return staker.balanceOf(want, address(this));
    }

    function balanceOfRewards()
        external
        view
        override
        returns (TokenAmount[] memory rewards)
    {
        // Rewards are 0
        rewards = new TokenAmount[](2);
        rewards[0] = TokenAmount(want, 0);
        rewards[1] = TokenAmount(reward, 0);
        return rewards;
    }
}
