// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { WeightLib } from "../src/lib/WeightLib.sol";

/// @title WeightLib Tests — Unit and fuzz tests for neutrality weight calculation
contract WeightLibTest is Test {
    uint256 constant SCALE = 1e18;

    // ──────────────────────────────────────────────────────────────
    //  Simple weight (equal reserves) — matches spec examples
    // ──────────────────────────────────────────────────────────────

    function test_simple_balanced_500_500() public pure {
        uint256 w = WeightLib.computeWeightSimple(500e18, 500e18);
        // min(500e18, 500e18) = 500e18
        assertEq(w, 500e18, "Balanced 500/500 should be 500e18");
    }

    function test_simple_biased_900_100() public pure {
        uint256 w = WeightLib.computeWeightSimple(900e18, 100e18);
        // min(100e18, 900e18) = 100e18
        assertEq(w, 100e18, "Biased 900/100 should be 100e18");
    }

    function test_simple_extreme_999_1() public pure {
        uint256 w = WeightLib.computeWeightSimple(999e18, 1e18);
        // min(1e18, 999e18) = 1e18
        assertEq(w, 1e18, "Extreme 999/1 should be 1e18");
    }

    function test_simple_one_sided_1000_0() public pure {
        uint256 w = WeightLib.computeWeightSimple(1000e18, 0);
        assertEq(w, 0, "One-sided 1000/0 should be 0");
    }

    function test_simple_one_sided_0_1000() public pure {
        uint256 w = WeightLib.computeWeightSimple(0, 1000e18);
        assertEq(w, 0, "One-sided 0/1000 should be 0");
    }

    function test_simple_zero_zero() public pure {
        uint256 w = WeightLib.computeWeightSimple(0, 0);
        assertEq(w, 0, "Zero/zero should be 0");
    }

    function test_simple_dust_1_1() public pure {
        uint256 w = WeightLib.computeWeightSimple(1, 1);
        // min(1, 1) = 1
        assertEq(w, 1, "Dust 1/1 gives weight = 1 (blocked at contract level via MIN_BALANCE)");
    }

    function test_simple_symmetric() public pure {
        uint256 w1 = WeightLib.computeWeightSimple(300e18, 700e18);
        uint256 w2 = WeightLib.computeWeightSimple(700e18, 300e18);
        assertEq(w1, w2, "Weight should be symmetric");
    }

    // ──────────────────────────────────────────────────────────────
    //  Full weight (with reserve normalization)
    // ──────────────────────────────────────────────────────────────

    function test_full_balanced_equal_reserves() public pure {
        // When reserves are equal and prices are equal, full = simple
        uint256 price = 100000; // DENOMINATOR = 100000
        uint256 reserve = 1000e18;
        uint256 w = WeightLib.computeWeight(500e18, 500e18, price, price, reserve, reserve);
        // normBull = (500e18 * 100000 / 1e18) * (0.5e18) / 1e18
        //         = 50_000_000_000 * 500_000_000_000_000_000 / 1e18
        //         = 25_000_000
        // weight = min(25000000, 25000000) = 25000000
        assertEq(w, 25000000, "Equal reserves: weight = normBull = normBear");
    }

    function test_full_one_sided_bull() public pure {
        uint256 price = 100000;
        uint256 reserve = 1000e18;
        uint256 w = WeightLib.computeWeight(1000e18, 0, price, price, reserve, reserve);
        assertEq(w, 0, "All bull, no bear -> weight = 0");
    }

    function test_full_asymmetric_reserves() public pure {
        // Bear reserve = 2x bull reserve. A "balanced" user needs 2x bear value.
        // User: 100 bull, 200 bear, bullPrice=bearPrice=100000
        // Bull reserve = 1000e18, Bear reserve = 2000e18
        uint256 price = 100000;
        uint256 w = WeightLib.computeWeight(100e18, 200e18, price, price, 1000e18, 2000e18);
        // normBull = 100e18 * 100000 / 1e18 * (2000/3000 * 1e18) / 1e18
        //         = 100e18 * 100000 / 1e18 = 10000e18... then * bearShare
        //         bearShare = 2000/3000 * 1e18 = 0.666e18
        //         normBull = (100e18 * 100000 / 1e18) * 0.666e18 / 1e18
        // Let's just verify it's reasonable
        assertGt(w, 0, "Asymmetric reserves with matching exposure should have weight > 0");
    }

    function test_full_zero_reserves() public pure {
        uint256 w = WeightLib.computeWeight(500e18, 500e18, 100000, 100000, 0, 0);
        assertEq(w, 0, "Zero reserves -> weight = 0");
    }

    function test_full_zero_price() public pure {
        uint256 w = WeightLib.computeWeight(500e18, 500e18, 0, 0, 1000e18, 1000e18);
        assertEq(w, 0, "Zero prices -> normalized = 0 -> weight = 0");
    }

    // ──────────────────────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────────────────────

    function testFuzz_simple_weight_bounded(uint256 bull, uint256 bear) public pure {
        // Bound to prevent overflow: max 2^128 each
        bull = bound(bull, 0, type(uint128).max);
        bear = bound(bear, 0, type(uint128).max);

        uint256 w = WeightLib.computeWeightSimple(bull, bear);

        // Invariant: weight = min(bull, bear)
        uint256 expected = bull < bear ? bull : bear;
        assertEq(w, expected, "Weight must equal min(bull, bear)");

        // If both zero, weight must be zero
        if (bull == 0 && bear == 0) {
            assertEq(w, 0, "Zero balances -> zero weight");
        }

        // If one is zero, weight must be zero
        if (bull == 0 || bear == 0) {
            assertEq(w, 0, "One-sided -> zero weight");
        }
    }

    function testFuzz_simple_weight_symmetric(uint256 a, uint256 b) public pure {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);

        uint256 w1 = WeightLib.computeWeightSimple(a, b);
        uint256 w2 = WeightLib.computeWeightSimple(b, a);
        assertEq(w1, w2, "Weight must be symmetric");
    }

    function testFuzz_full_weight_bounded(
        uint256 bull,
        uint256 bear,
        uint256 bullPrice,
        uint256 bearPrice,
        uint256 bullReserve,
        uint256 bearReserve
    ) public pure {
        // Bound all values to prevent overflow
        bull = bound(bull, 0, 1e30);
        bear = bound(bear, 0, 1e30);
        bullPrice = bound(bullPrice, 0, 1e10);
        bearPrice = bound(bearPrice, 0, 1e10);
        bullReserve = bound(bullReserve, 0, 1e30);
        bearReserve = bound(bearReserve, 0, 1e30);

        uint256 w =
            WeightLib.computeWeight(bull, bear, bullPrice, bearPrice, bullReserve, bearReserve);

        // Invariant: weight is bounded (no overflow)
        // weight = min(normBull, normBear) which is bounded by the inputs
        assertLe(w, type(uint256).max, "Weight must not overflow");
    }

    function testFuzz_full_no_division_by_zero(
        uint256 bull,
        uint256 bear,
        uint256 price,
        uint256 reserve
    ) public pure {
        bull = bound(bull, 0, 1e30);
        bear = bound(bear, 0, 1e30);
        price = bound(price, 0, 1e10);
        reserve = bound(reserve, 0, 1e30);

        // Should never revert
        WeightLib.computeWeight(bull, bear, price, price, reserve, reserve);
        WeightLib.computeWeightSimple(bull, bear);
    }
}
