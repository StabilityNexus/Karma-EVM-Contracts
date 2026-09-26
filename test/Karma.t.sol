// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Karma} from "../src/Karma.sol";
import {IKarmaOracle} from "../src/interfaces/IKarmaOracle.sol";
import {MockBaseToken, MockCoin, MockPredictionPool} from "./mocks/Mocks.sol";

/// @title Karma Tests -- Core contract tests for price submission, weight, IOracle, Chainlink compat
contract KarmaTest is Test {
    Karma public karma;
    MockBaseToken public baseToken;
    MockCoin public bullCoin;
    MockCoin public bearCoin;
    MockPredictionPool public pool;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public owner;

    uint256 constant TAU = 124651;
    uint256 constant MIN_BALANCE = 100e18;
    uint256 constant WAD = 1e18;

    function setUp() public {
        owner = address(this);

        // Deploy mock tokens
        baseToken = new MockBaseToken();
        bullCoin = new MockCoin("Bull", "BULL", address(baseToken));
        bearCoin = new MockCoin("Bear", "BEAR", address(baseToken));

        // Deploy mock pool
        pool = new MockPredictionPool(address(baseToken), address(bullCoin), address(bearCoin));

        // Seed reserves (equal 50/50 for simplicity)
        baseToken.mint(address(bullCoin), 10000e18);
        baseToken.mint(address(bearCoin), 10000e18);

        // Mint bull/bear coins to simulate supply (matching 1:1 with reserve)
        bullCoin.mint(address(this), 10000e18); // So priceSell = reserve/supply = 100000
        bearCoin.mint(address(this), 10000e18);

        // Deploy Karma
        karma = new Karma(address(pool), TAU, MIN_BALANCE, "Test Karma Oracle");

        // Give Alice balanced position
        bullCoin.mint(alice, 500e18);
        bearCoin.mint(alice, 500e18);

        // Give Bob biased position
        bullCoin.mint(bob, 900e18);
        bearCoin.mint(bob, 100e18);

        // Charlie has nothing (will get tokens as needed)
    }

    // ──────────────────────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────────────────────

    function test_constructor_state() public view {
        assertEq(address(karma.pool()), address(pool));
        assertEq(address(karma.baseToken()), address(baseToken));
        assertEq(karma.bullCoin(), address(bullCoin));
        assertEq(karma.bearCoin(), address(bearCoin));
        assertEq(karma.tau(), TAU);
        assertEq(karma.minTotalBalance(), MIN_BALANCE);
        assertEq(karma.submissionCount(), 0);
    }

    function test_constructor_zero_pool_reverts() public {
        vm.expectRevert(Karma.InvalidPool.selector);
        new Karma(address(0), TAU, MIN_BALANCE, "test");
    }

    function test_constructor_default_tau() public {
        Karma k = new Karma(address(pool), 0, 0, "defaults");
        assertEq(k.tau(), 124651, "Should use DEFAULT_TAU");
        assertEq(k.minTotalBalance(), 100e18, "Should use DEFAULT_MIN_BALANCE");
    }

    // ──────────────────────────────────────────────────────────────
    //  submitPrice — happy path
    // ──────────────────────────────────────────────────────────────

    function test_submitPrice_balanced_user() public {
        uint256 price = 67000e18;

        vm.prank(alice);
        karma.submitPrice(price);

        // Check submission stored
        (uint256 p, uint256 w, uint256 t) = karma.getSubmission(alice);
        assertEq(p, price, "Price should be stored");
        assertGt(w, 0, "Weight should be non-zero for balanced user");
        assertEq(t, block.timestamp, "Timestamp should be current");

        // Check readValue returns the submitted price
        assertEq(karma.readValue(), price, "Single submission -> readValue = price");

        // Check submission count
        assertEq(karma.submissionCount(), 1);
    }

    function test_submitPrice_emits_event() public {
        uint256 price = 67000e18;

        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit IKarmaOracle.PriceSubmitted(alice, price, 0, block.timestamp);
        karma.submitPrice(price);
    }

    function test_submitPrice_biased_user_lower_weight() public {
        uint256 price = 67000e18;

        vm.prank(alice);
        karma.submitPrice(price);
        (, uint256 aliceWeight,) = karma.getSubmission(alice);

        vm.prank(bob);
        karma.submitPrice(price);
        (, uint256 bobWeight,) = karma.getSubmission(bob);

        assertGt(aliceWeight, bobWeight, "Balanced Alice should have higher weight than biased Bob");
    }

    // ──────────────────────────────────────────────────────────────
    //  submitPrice — reverts
    // ──────────────────────────────────────────────────────────────

    function test_submitPrice_zero_price_reverts() public {
        vm.prank(alice);
        vm.expectRevert(Karma.ZeroPrice.selector);
        karma.submitPrice(0);
    }

    function test_submitPrice_insufficient_balance_reverts() public {
        // Charlie has no tokens
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(Karma.InsufficientBalance.selector, 0, MIN_BALANCE)
        );
        karma.submitPrice(67000e18);
    }

    function test_submitPrice_below_min_balance_reverts() public {
        // Give Charlie just below minimum
        bullCoin.mint(charlie, 49e18);
        bearCoin.mint(charlie, 49e18);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(Karma.InsufficientBalance.selector, 98e18, MIN_BALANCE)
        );
        karma.submitPrice(67000e18);
    }

    function test_submitPrice_one_sided_zero_weight_reverts() public {
        // Give Charlie only bull coins (enough for min balance but zero weight)
        bullCoin.mint(charlie, 200e18);
        // bearCoin = 0

        vm.prank(charlie);
        vm.expectRevert(Karma.ZeroWeight.selector);
        karma.submitPrice(67000e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  readValue — weighted average
    // ──────────────────────────────────────────────────────────────

    function test_readValue_no_submissions_reverts() public {
        vm.expectRevert("No price available");
        karma.readValue();
    }

    function test_readValue_multiple_users() public {
        // Alice (high weight) says 100, Bob (low weight) says 200
        vm.prank(alice);
        karma.submitPrice(100e18);

        vm.prank(bob);
        karma.submitPrice(200e18);

        uint256 price = karma.readValue();
        // Alice's weight > Bob's weight, so price should be closer to 100
        assertGt(price, 100e18, "Should be above 100");
        assertLt(price, 200e18, "Should be below 200");
        assertLt(price, 150e18, "Should be closer to Alice's price (higher weight)");
    }

    // ──────────────────────────────────────────────────────────────
    //  readValueInterval
    // ──────────────────────────────────────────────────────────────

    function test_readValueInterval() public {
        vm.prank(alice);
        karma.submitPrice(67000e18);

        (uint256 minVal, uint256 maxVal) = karma.readValueInterval();
        assertEq(minVal, maxVal, "Point estimate: min == max");
        assertEq(minVal, 67000e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  getWeight
    // ──────────────────────────────────────────────────────────────

    function test_getWeight_balanced() public view {
        uint256 w = karma.getWeight(alice);
        // Alice: 500/500 balanced with equal reserves
        // normBull = (500e18 * 100000 / 1e18) * (0.5e18) / 1e18 = 25000
        // weight = min(25000, 25000) = 25000
        assertGt(w, 0, "Balanced user should have non-zero weight");
    }

    function test_getWeight_biased() public view {
        uint256 w = karma.getWeight(bob);
        // Bob: 900/100 biased -> weight = min(normBull, normBear)
        // The smaller side determines the weight
        assertGt(w, 0, "Biased user > 0");
    }

    function test_getWeight_no_tokens() public view {
        uint256 w = karma.getWeight(charlie);
        assertEq(w, 0, "No tokens -> zero weight");
    }

    // ──────────────────────────────────────────────────────────────
    //  lastUpdated
    // ──────────────────────────────────────────────────────────────

    function test_lastUpdated_initial() public view {
        assertEq(karma.lastUpdated(), 0, "No submissions -> lastUpdated = 0");
    }

    function test_lastUpdated_after_submission() public {
        vm.warp(1000);
        vm.prank(alice);
        karma.submitPrice(67000e18);
        assertEq(karma.lastUpdated(), 1000);
    }

    // ──────────────────────────────────────────────────────────────
    //  description
    // ──────────────────────────────────────────────────────────────

    function test_description() public view {
        assertEq(karma.description(), "Test Karma Oracle");
    }

    // ──────────────────────────────────────────────────────────────
    //  hasPrice
    // ──────────────────────────────────────────────────────────────

    function test_hasPrice() public {
        assertFalse(karma.hasPrice(), "Initially no price");

        vm.prank(alice);
        karma.submitPrice(67000e18);

        assertTrue(karma.hasPrice(), "Should have price after submission");
    }

    // ──────────────────────────────────────────────────────────────
    //  Chainlink compatibility
    // ──────────────────────────────────────────────────────────────

    function test_latestRoundData() public {
        vm.warp(1000);
        vm.prank(alice);
        karma.submitPrice(67000e18);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = karma.latestRoundData();

        assertEq(roundId, 1, "First round");
        assertEq(answer, int256(67000e18), "Price as int256");
        assertEq(startedAt, 1000, "First submission time");
        assertEq(updatedAt, 1000, "Last update time");
        assertEq(answeredInRound, 1);
    }

    function test_decimals() public view {
        assertEq(karma.decimals(), 18);
    }

    function test_version() public view {
        assertEq(karma.version(), 1);
    }

    // ──────────────────────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────────────────────

    function test_setMinTotalBalance() public {
        karma.setMinTotalBalance(200e18);
        assertEq(karma.minTotalBalance(), 200e18);
    }

    function test_setMinTotalBalance_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit IKarmaOracle.MinBalanceUpdated(MIN_BALANCE, 200e18);
        karma.setMinTotalBalance(200e18);
    }

    function test_setMinTotalBalance_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        karma.setMinTotalBalance(200e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Multiple submissions over time (integration)
    // ──────────────────────────────────────────────────────────────

    function test_multiple_submissions_over_time() public {
        // Alice submits at t=0
        vm.prank(alice);
        karma.submitPrice(100e18);

        // Warp 1 hour
        vm.warp(block.timestamp + 3600);

        // Bob submits different price
        vm.prank(bob);
        karma.submitPrice(200e18);

        uint256 price = karma.readValue();
        // Alice has higher weight and was more recent-ish; both contribute
        assertGt(price, 100e18);
        assertLt(price, 200e18);
        assertEq(karma.submissionCount(), 2);
    }

    function test_overwrite_own_submission() public {
        vm.startPrank(alice);
        karma.submitPrice(100e18);

        vm.warp(block.timestamp + 60);
        karma.submitPrice(200e18);
        vm.stopPrank();

        (uint256 p,,) = karma.getSubmission(alice);
        assertEq(p, 200e18, "Latest submission overwrites previous");
        assertEq(karma.submissionCount(), 2, "Counter increments for each submission");
    }
}
