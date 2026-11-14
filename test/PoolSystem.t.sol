// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccumulatorVault } from "../src/AccumulatorVault.sol";
import { ChainlinkAdapterFactory } from "../src/ChainlinkAdapterFactory.sol";
import { Coin } from "../src/Coin.sol";
import { Karma } from "../src/Karma.sol";
import { KarmaAdapterFactory } from "../src/KarmaAdapterFactory.sol";
import { PredictionPool } from "../src/PredictionPool.sol";
import { PredictionPoolFactory } from "../src/PredictionPoolFactory.sol";
import { ChainlinkOracle } from "../src/oracles/ChainlinkOracle.sol";
import { IAggregatorV3 } from "../src/interfaces/IAggregatorV3.sol";
import { IOracle } from "../src/interfaces/IOracle.sol";
import { MockBaseToken, MockFeeOnTransferToken } from "./mocks/Mocks.sol";

contract MockFeed is IAggregatorV3 {
    uint8 public immutable override decimals;
    string public override description = "Test feed";
    int256 public answer;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        answer = answer_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

contract MockOracle is IOracle {
    uint256 public value;

    constructor(uint256 initialValue) {
        value = initialValue;
    }

    function setValue(uint256 newValue) external {
        value = newValue;
    }

    function readValue() external view returns (uint256) {
        return value;
    }

    function readValueInterval() external view returns (uint256, uint256) {
        return (value, value);
    }

    function lastUpdated() external view returns (uint256) {
        return block.timestamp;
    }

    function description() external pure returns (string memory) {
        return "Test oracle";
    }
}

contract PoolSystemTest is Test {
    uint256 private constant INITIAL_DEPOSIT = 1_000e18;
    uint256 private constant MINT_FEE = 500;
    uint256 private constant BURN_FEE = 500;
    uint256 private constant CREATOR_FEE = 500;
    uint256 private constant DEV_FEE = 300;

    address private dev = makeAddr("dev");
    address private receiver = makeAddr("receiver");
    address private nextDev = makeAddr("nextDev");
    address private nextReceiver = makeAddr("nextReceiver");
    address private trader = makeAddr("trader");

    MockBaseToken private baseToken;
    MockOracle private initialOracle;
    AccumulatorVault private vault;
    PredictionPoolFactory private poolFactory;
    PredictionPool private pool;
    Coin private bull;
    Coin private bear;

    function setUp() public {
        baseToken = new MockBaseToken();
        initialOracle = new MockOracle(1e18);
        vault = new AccumulatorVault(dev, receiver);
        poolFactory = new PredictionPoolFactory(address(vault));

        baseToken.mint(address(this), INITIAL_DEPOSIT);
        baseToken.approve(address(poolFactory), type(uint256).max);
        pool = PredictionPool(
            poolFactory.createPool(
                "Karma market",
                address(baseToken),
                address(initialOracle),
                "Bull",
                "BULL",
                "Bear",
                "BEAR",
                MINT_FEE,
                BURN_FEE,
                CREATOR_FEE,
                DEV_FEE,
                INITIAL_DEPOSIT
            )
        );
        bull = pool.bullCoin();
        bear = pool.bearCoin();
    }

    function test_poolCreationSetsFeesAndInitialLiquidity() public view {
        assertEq(pool.owner(), address(this));
        assertEq(address(pool.accumulatorVault()), address(vault));
        assertEq(pool.devFee(), DEV_FEE);
        assertEq(bull.devFee(), DEV_FEE);
        assertEq(bear.devFee(), DEV_FEE);
        assertEq(baseToken.balanceOf(address(bull)), INITIAL_DEPOSIT / 2);
        assertEq(baseToken.balanceOf(address(bear)), INITIAL_DEPOSIT / 2);
        assertEq(bull.balanceOf(address(this)), INITIAL_DEPOSIT / 2);
        assertEq(bear.balanceOf(address(this)), INITIAL_DEPOSIT / 2);
        assertEq(poolFactory.getPoolCount(), 1);
    }

    function test_chainlinkAdapterScalesAndCachesFeed() public {
        MockFeed feed = new MockFeed(8, 2_500e8);
        ChainlinkAdapterFactory factory = new ChainlinkAdapterFactory();

        address adapter = factory.createAdapter(address(feed));
        ChainlinkOracle oracle = ChainlinkOracle(adapter);

        assertEq(oracle.readValue(), 2_500e18);
        assertEq(factory.getAdapter(address(feed)), adapter);
        assertEq(factory.createAdapter(address(feed)), adapter);
    }

    function test_devCanUpdateReceiverAndTransferRoleInTwoSteps() public {
        vm.prank(dev);
        vault.setDevFeeReceiver(nextReceiver);
        assertEq(vault.devFeeReceiver(), nextReceiver);

        vm.prank(dev);
        vault.proposeDevTransfer(nextDev);
        assertEq(vault.pendingDev(), nextDev);

        vm.expectRevert(AccumulatorVault.NotPendingDev.selector);
        vault.acceptDevTransfer();

        vm.prank(nextDev);
        vault.acceptDevTransfer();
        assertEq(vault.dev(), nextDev);
        assertEq(vault.pendingDev(), address(0));
    }

    function test_devFeesAccumulateAndFlushToReceiver() public {
        uint256 amountIn = 100e18;
        baseToken.mint(trader, amountIn);
        vm.startPrank(trader);
        baseToken.approve(address(bull), amountIn);
        bull.buy(trader, amountIn);
        vm.stopPrank();

        uint256 expectedDevFee = (amountIn * DEV_FEE) / 100_000;
        assertEq(baseToken.balanceOf(address(vault)), expectedDevFee);
        assertEq(baseToken.balanceOf(receiver), 0);

        vm.prank(dev);
        vault.flushToken(address(baseToken));
        assertEq(baseToken.balanceOf(address(vault)), 0);
        assertEq(baseToken.balanceOf(receiver), expectedDevFee);
    }

    function test_sellChargesAndAccumulatesDevFee() public {
        uint256 amountIn = 100e18;
        baseToken.mint(trader, amountIn);
        vm.startPrank(trader);
        baseToken.approve(address(bull), amountIn);
        uint256 coinOut = bull.buy(trader, amountIn);
        uint256 amountOut = bull.sell(coinOut / 2);
        vm.stopPrank();

        assertGt(amountOut, 0);
        assertGt(baseToken.balanceOf(address(vault)), (amountIn * DEV_FEE) / 100_000);
    }

    function test_karmaCanBeCreatedForPoolAndSetAsOracle() public {
        KarmaAdapterFactory karmaFactory = new KarmaAdapterFactory();
        address karmaAddress = karmaFactory.createKarma(address(pool), 0, 0, "Karma");
        Karma karma = Karma(karmaAddress);

        karma.submitPrice(150e18);
        pool.updateOracle(karmaAddress);

        assertEq(address(pool.oracle()), karmaAddress);
        assertEq(pool.getCurrentPrice(), 150e18);
    }

    function test_onlyPoolCanChangeCoinPairOrMoveReserves() public {
        vm.expectRevert(Coin.OnlyPredictionPool.selector);
        bull.setOtherCoin(address(0x1234));

        vm.expectRevert(Coin.OnlyPredictionPool.selector);
        bull.transferReserveToOther(1);
    }

    event Rebalanced(
        address indexed caller,
        uint256 indexed blockNumber,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 priceChangePercent,
        uint256 bullReservesBefore,
        uint256 bearReservesBefore,
        uint256 bullReservesAfter,
        uint256 bearReservesAfter,
        uint256 transferAmount,
        bool wasTransferToBull,
        uint256 timestamp
    );

    function test_rebalanceEmitsAccurateReserves() public {
        initialOracle.setValue(2e18);
        uint256 bullBefore = baseToken.balanceOf(address(bull));
        uint256 bearBefore = baseToken.balanceOf(address(bear));

        uint256 expectedTransfer = 300e18;
        uint256 expectedBullAfter = bullBefore + expectedTransfer;
        uint256 expectedBearAfter = bearBefore - expectedTransfer;

        vm.expectEmit(true, true, false, true, address(pool));
        emit Rebalanced(
            address(this),
            block.number,
            1e18,
            2e18,
            10_000,
            bullBefore,
            bearBefore,
            expectedBullAfter,
            expectedBearAfter,
            expectedTransfer,
            true,
            block.timestamp
        );

        pool.rebalance();

        uint256 bullAfter = baseToken.balanceOf(address(bull));
        uint256 bearAfter = baseToken.balanceOf(address(bear));
        assertEq(bullAfter, expectedBullAfter);
        assertEq(bearAfter, expectedBearAfter);
        assertEq(bullAfter, 800e18);
        assertEq(bearAfter, 200e18);
    }

    function test_rebalanceEmitsAccurateReserves_transferToBear() public {
        initialOracle.setValue(5e17);
        uint256 bullBefore = baseToken.balanceOf(address(bull));
        uint256 bearBefore = baseToken.balanceOf(address(bear));

        uint256 expectedTransfer = 300e18;
        uint256 expectedBullAfter = bullBefore - expectedTransfer;
        uint256 expectedBearAfter = bearBefore + expectedTransfer;

        vm.expectEmit(true, true, false, true, address(pool));
        emit Rebalanced(
            address(this),
            block.number,
            1e18,
            5e17,
            5_000,
            bullBefore,
            bearBefore,
            expectedBullAfter,
            expectedBearAfter,
            expectedTransfer,
            false,
            block.timestamp
        );

        pool.rebalance();

        uint256 bullAfter = baseToken.balanceOf(address(bull));
        uint256 bearAfter = baseToken.balanceOf(address(bear));
        assertEq(bullAfter, expectedBullAfter);
        assertEq(bearAfter, expectedBearAfter);
        assertEq(bullAfter, 200e18);
        assertEq(bearAfter, 800e18);
    }

    function test_rebalance_zeroTransferWhenPriceUnchanged() public {
        uint256 bullBefore = baseToken.balanceOf(address(bull));
        uint256 bearBefore = baseToken.balanceOf(address(bear));

        pool.rebalance();

        assertEq(baseToken.balanceOf(address(bull)), bullBefore);
        assertEq(baseToken.balanceOf(address(bear)), bearBefore);
        assertEq(pool.previousPrice(), 1e18);
    }

    function _createPoolWithToken(address token) private {
        poolFactory.createPool(
            "FOT pool",
            token,
            address(initialOracle),
            "Bull",
            "BULL",
            "Bear",
            "BEAR",
            MINT_FEE,
            BURN_FEE,
            CREATOR_FEE,
            DEV_FEE,
            INITIAL_DEPOSIT
        );
    }

    function test_createPool_revertsOnFeeOnTransferToken() public {
        MockFeeOnTransferToken fotToken = new MockFeeOnTransferToken();
        fotToken.mint(address(this), INITIAL_DEPOSIT);
        fotToken.approve(address(poolFactory), type(uint256).max);

        vm.expectRevert(PredictionPoolFactory.FeeOnTransferNotSupported.selector);
        _createPoolWithToken(address(fotToken));
    }

    function test_createPool_revertsOnFeeOnTransferToken_poolDepositCheck() public {
        MockFeeOnTransferToken fotToken = new MockFeeOnTransferToken();
        fotToken.mint(address(this), INITIAL_DEPOSIT);
        fotToken.approve(address(poolFactory), type(uint256).max);

        // Exempt factory transferFrom so factory check passes;
        // Pool's safeTransferFrom in initialize is taxed and triggers line 172 check.
        fotToken.setExemptRecipient(address(poolFactory));

        vm.expectRevert(PredictionPool.FeeOnTransferNotSupported.selector);
        _createPoolWithToken(address(fotToken));
    }

    function test_createPool_revertsOnFeeOnTransferToken_bullDepositCheck() public {
        MockFeeOnTransferToken fotToken = new MockFeeOnTransferToken();
        fotToken.mint(address(this), INITIAL_DEPOSIT);
        fotToken.approve(address(poolFactory), type(uint256).max);

        // Disable transferFrom fee so factory pull and pool pull both succeed;
        // Tax 1st transfer (pool -> bullCoin deposit) to trigger line 177 check.
        fotToken.setFeeOnTransferFrom(false);
        fotToken.setTaxOnlyTransferIndex(1);

        vm.expectRevert(PredictionPool.FeeOnTransferNotSupported.selector);
        _createPoolWithToken(address(fotToken));
    }

    function test_createPool_revertsOnFeeOnTransferToken_bearDepositCheck() public {
        MockFeeOnTransferToken fotToken = new MockFeeOnTransferToken();
        fotToken.mint(address(this), INITIAL_DEPOSIT);
        fotToken.approve(address(poolFactory), type(uint256).max);

        // Disable transferFrom fee so factory pull and pool pull both succeed;
        // Tax 2nd transfer (pool -> bearCoin deposit) to trigger line 182 check.
        fotToken.setFeeOnTransferFrom(false);
        fotToken.setTaxOnlyTransferIndex(2);

        vm.expectRevert(PredictionPool.FeeOnTransferNotSupported.selector);
        _createPoolWithToken(address(fotToken));
    }
}
