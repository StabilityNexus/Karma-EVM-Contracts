// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { AccumulatorVault } from "../src/AccumulatorVault.sol";
import { Coin } from "../src/Coin.sol";
import { PredictionPool } from "../src/PredictionPool.sol";
import { PredictionPoolFactory } from "../src/PredictionPoolFactory.sol";
import { MockBaseToken } from "./mocks/Mocks.sol";
import { MockOracle } from "./PoolSystem.t.sol";

// Neither coin may start empty, or its first buyer takes the reserve it holds.
contract PoolInitialDepositTest is Test {
    uint256 private constant MINT_FEE = 500;
    uint256 private constant BURN_FEE = 500;
    uint256 private constant CREATOR_FEE = 500;
    uint256 private constant DEV_FEE = 300;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    MockBaseToken private baseToken;
    MockOracle private oracle;
    PredictionPoolFactory private poolFactory;

    function setUp() public {
        baseToken = new MockBaseToken();
        oracle = new MockOracle(1e18);
        poolFactory = new PredictionPoolFactory(
            address(new AccumulatorVault(makeAddr("dev"), makeAddr("receiver")))
        );
        baseToken.mint(address(this), 1_000e18);
        baseToken.approve(address(poolFactory), type(uint256).max);
        baseToken.mint(alice, 1_000e18);
        baseToken.mint(bob, 1e18);
    }

    function test_zeroDepositReverts() public {
        vm.expectRevert(PredictionPool.InitialDepositTooSmall.selector);
        _createPool(0);
    }

    function test_oneWeiDepositReverts() public {
        // 1 / 2 = 0 would leave the bull coin without supply.
        vm.expectRevert(PredictionPool.InitialDepositTooSmall.selector);
        _createPool(1);
    }

    function test_twoWeiDepositGivesBothCoinsSupply() public {
        PredictionPool pool = _createPool(2);

        assertEq(pool.bullCoin().totalSupply(), 1);
        assertEq(pool.bearCoin().totalSupply(), 1);
    }

    function test_buyerOfFundedSideGetsOnlyOwnShare() public {
        PredictionPool pool = _createPool(1_000e18);
        Coin bear = _moveValueIntoBear(pool);

        vm.startPrank(bob);
        baseToken.approve(address(bear), 1e18);
        uint256 coins = bear.buy(bob, 1e18);
        uint256 assetOut = bear.sell(coins);
        vm.stopPrank();

        // Bob only loses the 1.3% fees each way and gets no part of the existing reserve.
        assertLt(assetOut, 1e18);
        assertGt(assetOut, 0.97e18);
    }

    function _moveValueIntoBear(PredictionPool pool) private returns (Coin bear) {
        Coin bull = pool.bullCoin();
        bear = pool.bearCoin();

        vm.startPrank(alice);
        baseToken.approve(address(bull), 1_000e18);
        bull.buy(alice, 1_000e18);
        vm.stopPrank();

        oracle.setValue(0.5e18);
        pool.rebalance();
    }

    function _createPool(uint256 initialDeposit) private returns (PredictionPool) {
        return PredictionPool(
            poolFactory.createPool(
                "Karma market",
                address(baseToken),
                address(oracle),
                "Bull",
                "BULL",
                "Bear",
                "BEAR",
                MINT_FEE,
                BURN_FEE,
                CREATOR_FEE,
                DEV_FEE,
                initialDeposit
            )
        );
    }
}
