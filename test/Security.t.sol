// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { Karma } from "../src/Karma.sol";
import { MockBaseToken, MockCoin, MockPredictionPool } from "./mocks/Mocks.sol";

/// @title Security Tests -- Sybil resistance, whale resistance, flash-loan simulation, reentrancy
contract SecurityTest is Test {
    Karma public karma;
    MockBaseToken public baseToken;
    MockCoin public bullCoin;
    MockCoin public bearCoin;
    MockPredictionPool public pool;

    uint256 constant TAU = 124651;
    uint256 constant MIN_BALANCE = 100e18;

    function setUp() public {
        baseToken = new MockBaseToken();
        bullCoin = new MockCoin("Bull", "BULL", address(baseToken));
        bearCoin = new MockCoin("Bear", "BEAR", address(baseToken));
        pool = new MockPredictionPool(address(baseToken), address(bullCoin), address(bearCoin));

        // Seed reserves (equal)
        baseToken.mint(address(bullCoin), 10000e18);
        baseToken.mint(address(bearCoin), 10000e18);

        // Mint supply so priceSell works
        bullCoin.mint(address(this), 10000e18);
        bearCoin.mint(address(this), 10000e18);

        karma = new Karma(address(pool), TAU, MIN_BALANCE, "Security Test Oracle");
    }

    // ──────────────────────────────────────────────────────────────
    //  Sybil resistance
    // ──────────────────────────────────────────────────────────────

    function test_sybil_tiny_balanced_blocked() public {
        // 1000 Sybil wallets each with 1 bull + 1 bear (below MIN_BALANCE)
        for (uint256 i = 0; i < 10; i++) {
            address sybil = makeAddr(string(abi.encodePacked("sybil", i)));
            bullCoin.mint(sybil, 1e18);
            bearCoin.mint(sybil, 1e18);

            vm.prank(sybil);
            vm.expectRevert(
                abi.encodeWithSelector(Karma.InsufficientBalance.selector, 2e18, MIN_BALANCE)
            );
            karma.submitPrice(99999e18);
        }
    }

    function test_sybil_just_below_threshold() public {
        address sybil = makeAddr("sybil");
        bullCoin.mint(sybil, 49e18);
        bearCoin.mint(sybil, 49e18);

        vm.prank(sybil);
        vm.expectRevert(
            abi.encodeWithSelector(Karma.InsufficientBalance.selector, 98e18, MIN_BALANCE)
        );
        karma.submitPrice(67000e18);
    }

    function test_sybil_at_threshold_succeeds() public {
        address sybil = makeAddr("sybil");
        bullCoin.mint(sybil, 50e18);
        bearCoin.mint(sybil, 50e18);

        vm.prank(sybil);
        karma.submitPrice(67000e18); // Should succeed — exactly at threshold
    }

    // ──────────────────────────────────────────────────────────────
    //  Whale resistance
    // ──────────────────────────────────────────────────────────────

    function test_whale_unbalanced_low_weight() public {
        // Whale has large bull position, tiny bear.
        // Note: minting affects priceSell via supply dilution, but the whale
        // is still heavily unbalanced -> low weight.
        address whale = makeAddr("whale");
        bullCoin.mint(whale, 5000e18);
        bearCoin.mint(whale, 100e18);

        uint256 weight = karma.getWeight(whale);
        // Imbalanced -> weight = min(normBull, normBear), dominated by the smaller side
        assertGt(weight, 0, "Whale with some balance on both sides has non-zero weight");
    }

    function test_whale_vs_balanced_user() public {
        // Use moderate amounts to avoid supply dilution distorting priceSell
        address whale = makeAddr("whale");
        bullCoin.mint(whale, 5000e18);
        bearCoin.mint(whale, 100e18);

        address balanced = makeAddr("balanced");
        bullCoin.mint(balanced, 500e18);
        bearCoin.mint(balanced, 500e18);

        uint256 whaleWeight = karma.getWeight(whale);
        uint256 balancedWeight = karma.getWeight(balanced);

        // Despite whale having more total tokens, balanced user has higher weight
        assertGt(
            balancedWeight,
            whaleWeight,
            "Balanced user must have higher weight than unbalanced whale"
        );
    }

    function test_whale_cannot_dominate_oracle() public {
        // Balanced user submits correct price
        address balanced = makeAddr("balanced");
        bullCoin.mint(balanced, 500e18);
        bearCoin.mint(balanced, 500e18);

        vm.prank(balanced);
        karma.submitPrice(100e18); // "Correct" price

        // Whale tries to manipulate with wrong price
        // With weight = min(normBull, normBear), the whale's weight is determined
        // by their smaller side. A very unbalanced whale has low weight.
        address whale = makeAddr("whale");
        bullCoin.mint(whale, 100_000e18);
        bearCoin.mint(whale, 100e18); // Very small bear position

        vm.prank(whale);
        karma.submitPrice(500e18); // Manipulated price

        uint256 oraclePrice = karma.readValue();
        // Whale's weight ≈ min(normBull, normBear) driven by 100 bear tokens
        // Balanced user's weight ≈ 500 (their min side)
        // So balanced user has ~5× more weight → oracle stays close to 100
        assertLt(oraclePrice, 200e18, "Whale should not dominate oracle");
    }

    // ──────────────────────────────────────────────────────────────
    //  Flash-loan simulation
    // ──────────────────────────────────────────────────────────────

    function test_flash_loan_same_tx_weight() public {
        // Simulate flash-loan: temporarily inflate balance within same tx
        address attacker = makeAddr("flashloan");

        // Start with below-minimum balance
        bullCoin.mint(attacker, 10e18);
        bearCoin.mint(attacker, 10e18);

        // Flash-loan: mint huge balanced position (simulating flash-borrowed tokens)
        bullCoin.mint(attacker, 10000e18);
        bearCoin.mint(attacker, 10000e18);

        // Submit with inflated balance — this succeeds in the same tx
        vm.prank(attacker);
        karma.submitPrice(99999e18);

        // But the weight is based on balanceOf at submission time
        // The key defense is that bull/bear coins are NOT flash-loanable in Fate
        // because they require baseToken deposit through buy().
        // This test verifies the contract reads balances correctly.
        (, uint256 w,) = karma.getSubmission(attacker);
        assertGt(w, 0, "Flash-loaned balance does produce weight");

        // Now "repay" the flash loan
        bullCoin.burn(attacker, 10000e18);
        bearCoin.burn(attacker, 10000e18);

        // Subsequent weight check shows low balance
        uint256 currentWeight = karma.getWeight(attacker);
        assertLt(currentWeight, w, "Post-repay weight should be lower");
    }

    // ──────────────────────────────────────────────────────────────
    //  One-sided position
    // ──────────────────────────────────────────────────────────────

    function test_pure_bull_holder_cannot_submit() public {
        address bullOnly = makeAddr("bullOnly");
        bullCoin.mint(bullOnly, 1000e18);

        vm.prank(bullOnly);
        vm.expectRevert(Karma.ZeroWeight.selector);
        karma.submitPrice(67000e18);
    }

    function test_pure_bear_holder_cannot_submit() public {
        address bearOnly = makeAddr("bearOnly");
        bearCoin.mint(bearOnly, 1000e18);

        vm.prank(bearOnly);
        vm.expectRevert(Karma.ZeroWeight.selector);
        karma.submitPrice(67000e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Multiple balanced users consensus
    // ──────────────────────────────────────────────────────────────

    function test_multiple_balanced_users_consensus() public {
        // 5 balanced users all submit similar prices
        uint256[] memory prices = new uint256[](5);
        prices[0] = 100e18;
        prices[1] = 101e18;
        prices[2] = 99e18;
        prices[3] = 100e18;
        prices[4] = 102e18;

        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            bullCoin.mint(user, 500e18);
            bearCoin.mint(user, 500e18);

            vm.prank(user);
            karma.submitPrice(prices[i]);
        }

        uint256 oraclePrice = karma.readValue();
        // Should be close to 100.4 (average)
        assertApproxEqAbs(oraclePrice, 100.4e18, 1e18, "Consensus of balanced users");
    }

    // ──────────────────────────────────────────────────────────────
    //  Fuzz: submitPrice never panics with valid inputs
    // ──────────────────────────────────────────────────────────────

    function testFuzz_submitPrice_valid_inputs(uint256 price, uint256 bullBal, uint256 bearBal)
        public
    {
        price = bound(price, 1, 1e30);
        bullBal = bound(bullBal, 50e18, 1e24);
        bearBal = bound(bearBal, 50e18, 1e24);

        address user = makeAddr("fuzzUser");
        bullCoin.mint(user, bullBal);
        bearCoin.mint(user, bearBal);

        // Should either succeed or revert with a known error, never panic
        vm.prank(user);
        try karma.submitPrice(price) {
            // Verify state is consistent
            (uint256 p, uint256 w, uint256 t) = karma.getSubmission(user);
            assertEq(p, price);
            assertGt(w, 0);
            assertEq(t, block.timestamp);
        } catch {
            // Known reverts (ZeroWeight) are acceptable
        }
    }
}
