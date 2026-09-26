// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {PriceAverager} from "../src/lib/PriceAverager.sol";

/// @title PriceAverager Tests — Unit and fuzz tests for time-decayed price averaging
/// @dev   Uses a wrapper contract because PriceAverager operates on storage state.
contract PriceAveragerWrapper {
    using PriceAverager for PriceAverager.State;

    PriceAverager.State public state;

    uint256 public constant DEFAULT_TAU = 124651;

    function update(uint256 price, uint256 weight, uint256 tau) external {
        state.update(price, weight, tau);
    }

    function getPrice(uint256 tau) external view returns (uint256) {
        return state.getPrice(tau);
    }

    function hasPrice() external view returns (bool) {
        return state.hasPrice();
    }

    function getState()
        external
        view
        returns (uint256 weightedPrice, uint256 totalWeight, uint64 lastUpdateTime)
    {
        return (state.weightedPrice, state.totalWeight, state.lastUpdateTime);
    }
}

contract PriceAveragerTest is Test {
    PriceAveragerWrapper wrapper;
    uint256 constant WAD = 1e18;
    uint256 constant TAU = 124651; // ~1-day half-life

    function setUp() public {
        wrapper = new PriceAveragerWrapper();
    }

    // ──────────────────────────────────────────────────────────────
    //  Initial state
    // ──────────────────────────────────────────────────────────────

    function test_initial_no_price() public {
        assertFalse(wrapper.hasPrice(), "Should have no price initially");
    }

    function test_initial_getPrice_reverts() public {
        vm.expectRevert("No price available");
        wrapper.getPrice(TAU);
    }

    // ──────────────────────────────────────────────────────────────
    //  Single submission
    // ──────────────────────────────────────────────────────────────

    function test_single_submission() public {
        uint256 price = 67000e18;
        uint256 weight = 0.5e18;

        wrapper.update(price, weight, TAU);

        assertTrue(wrapper.hasPrice(), "Should have price after submission");
        assertEq(wrapper.getPrice(TAU), price, "Single submission -> exact price");
    }

    function test_zero_weight_ignored() public {
        wrapper.update(67000e18, 0, TAU);
        assertFalse(wrapper.hasPrice(), "Zero weight should not count as submission");
    }

    // ──────────────────────────────────────────────────────────────
    //  Multiple submissions (same timestamp)
    // ──────────────────────────────────────────────────────────────

    function test_two_equal_weight_same_time() public {
        uint256 w = 0.5e18;

        wrapper.update(100e18, w, TAU);
        wrapper.update(200e18, w, TAU);

        // With dt=0 between submissions, decay=1.0, so both contribute equally
        // weighted avg = (100*0.5 + 200*0.5) / (0.5 + 0.5) = 150
        uint256 result = wrapper.getPrice(TAU);
        assertApproxEqAbs(result, 150e18, 1e15, "Equal weight average should be 150");
    }

    function test_two_different_weight_same_time() public {
        // Alice: weight=0.5, price=100. Bob: weight=0.1, price=200
        wrapper.update(100e18, 0.5e18, TAU);
        wrapper.update(200e18, 0.1e18, TAU);

        // weighted avg = (100*0.5 + 200*0.1) / (0.5 + 0.1) = 70/0.6 ≈ 116.67
        uint256 result = wrapper.getPrice(TAU);
        assertApproxEqAbs(result, 116666666666666666666, 1e15, "Weighted avg ~= 116.67");
    }

    // ──────────────────────────────────────────────────────────────
    //  Time decay
    // ──────────────────────────────────────────────────────────────

    function test_decay_fresh_submission_dominates() public {
        // Old submission
        wrapper.update(100e18, 0.5e18, TAU);

        // Warp 1 day forward
        vm.warp(block.timestamp + 86400);

        // New submission
        wrapper.update(200e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice(TAU);
        // Old submission should be heavily decayed, new should dominate
        assertGt(result, 150e18, "Fresh submission should pull price toward 200");
        assertLt(result, 200e18, "Old submission should still have some influence");
    }

    function test_decay_very_old_almost_zero() public {
        wrapper.update(100e18, 0.5e18, TAU);

        // Warp 10 days forward — old submission should be nearly decayed
        vm.warp(block.timestamp + 864000);

        wrapper.update(500e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice(TAU);
        // After 10 days with tau ~1 day, decay ≈ exp(-10/1.44) ≈ 0.001
        assertApproxEqAbs(result, 500e18, 5e18, "Very old submission nearly irrelevant");
    }

    function test_decay_no_time_elapsed() public {
        wrapper.update(100e18, 0.5e18, TAU);
        wrapper.update(200e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice(TAU);
        // No decay since dt=0
        assertApproxEqAbs(result, 150e18, 1e15, "No time elapsed -> no decay -> simple avg");
    }

    // ──────────────────────────────────────────────────────────────
    //  Edge cases
    // ──────────────────────────────────────────────────────────────

    function test_large_delta_t() public {
        wrapper.update(100e18, 0.5e18, TAU);

        // Warp 1 year
        vm.warp(block.timestamp + 365 days);

        // Old data is completely decayed — new submission is all that matters
        wrapper.update(42e18, 0.1e18, TAU);

        uint256 result = wrapper.getPrice(TAU);
        assertApproxEqAbs(result, 42e18, 1e16, "After 1 year, old data fully decayed");
    }

    function test_many_submissions_different_times() public {
        // Submit prices over 5 consecutive blocks with time gaps
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 3600); // 1 hour gap
            wrapper.update((100 + i * 10) * 1e18, 0.3e18, TAU);
        }

        uint256 result = wrapper.getPrice(TAU);
        // Latest price is 140, should be close to recent prices
        assertGt(result, 100e18, "Should be above earliest price");
        assertLt(result, 150e18, "Should be below latest + margin");
    }

    // ──────────────────────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────────────────────

    function testFuzz_single_submission_returns_exact(uint256 price, uint256 weight) public {
        price = bound(price, 1e15, 1e30);
        weight = bound(weight, 1e12, 0.5e18);

        wrapper.update(price, weight, TAU);

        uint256 result = wrapper.getPrice(TAU);
        // Fixed-point rounding: (price * weight / WAD) * WAD / weight
        assertApproxEqRel(result, price, 1e14, "Single submission must return ~exact price");
    }

    function testFuzz_price_always_positive(
        uint256 p1,
        uint256 w1,
        uint256 p2,
        uint256 w2,
        uint256 timeDelta
    ) public {
        p1 = bound(p1, 1e15, 1e30);
        w1 = bound(w1, 1e12, 0.5e18);
        p2 = bound(p2, 1e15, 1e30);
        w2 = bound(w2, 1e12, 0.5e18);
        timeDelta = bound(timeDelta, 0, 30 days);

        wrapper.update(p1, w1, TAU);
        vm.warp(block.timestamp + timeDelta);
        wrapper.update(p2, w2, TAU);

        uint256 result = wrapper.getPrice(TAU);
        assertGt(result, 0, "Price must always be positive");
    }

    function testFuzz_no_overflow(uint256 price, uint256 weight) public {
        price = bound(price, 1, 1e30);
        weight = bound(weight, 1, 0.5e18);

        // Should never revert from overflow
        wrapper.update(price, weight, TAU);
        wrapper.getPrice(TAU);
    }
}
