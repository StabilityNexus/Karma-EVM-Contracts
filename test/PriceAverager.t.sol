// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { PriceAverager } from "../src/lib/PriceAverager.sol";

// Thin wrapper to expose PriceAverager library methods for testing.
contract PriceAveragerWrapper {
    using PriceAverager for PriceAverager.State;

    PriceAverager.State public state;

    uint256 public constant DEFAULT_TAU = 124651;

    function update(uint256 price, uint256 weight, uint256 tau) external {
        state.update(price, weight, tau);
    }

    function removeContribution(
        uint256 prevPrice,
        uint256 prevWeight,
        uint64 prevTimestamp,
        uint256 tau
    ) external {
        state.removeContribution(prevPrice, prevWeight, prevTimestamp, tau);
    }

    function getPrice() external view returns (uint256) {
        return state.getPrice();
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

// Unit and fuzz tests for PriceAverager.
contract PriceAveragerTest is Test {
    PriceAveragerWrapper wrapper;
    uint256 constant WAD = 1e18;
    uint256 constant TAU = 124651; // ~1-day half-life

    function setUp() public {
        wrapper = new PriceAveragerWrapper();
    }

    // -- Initial state --

    function test_initial_no_price() public view {
        assertFalse(wrapper.hasPrice(), "Should have no price initially");
    }

    function test_initial_getPrice_returns_zero() public view {
        assertEq(wrapper.getPrice(), 0, "Initial price should be 0");
    }

    // -- Single submission --

    function test_single_submission() public {
        uint256 price = 67000e18;
        uint256 weight = 0.5e18;

        wrapper.update(price, weight, TAU);

        assertTrue(wrapper.hasPrice(), "Should have price after submission");
        assertEq(wrapper.getPrice(), price, "Single submission -> exact price");
    }

    function test_zero_weight_ignored() public {
        wrapper.update(67000e18, 0, TAU);
        assertFalse(wrapper.hasPrice(), "Zero weight should not count as submission");
    }

    // -- Multiple submissions --

    function test_two_equal_weight_same_time() public {
        uint256 w = 0.5e18;

        wrapper.update(100e18, w, TAU);
        wrapper.update(200e18, w, TAU);

        uint256 result = wrapper.getPrice();
        assertApproxEqAbs(result, 150e18, 1e15, "Equal weight average should be 150");
    }

    function test_two_different_weight_same_time() public {
        wrapper.update(100e18, 0.5e18, TAU);
        wrapper.update(200e18, 0.1e18, TAU);

        // weighted avg = (100*0.5 + 200*0.1) / (0.5 + 0.1) = 70/0.6 ~= 116.67
        uint256 result = wrapper.getPrice();
        assertApproxEqAbs(result, 116666666666666666666, 1e15, "Weighted avg ~= 116.67");
    }

    // -- Resubmission / Remove contribution --

    function test_remove_contribution_on_resubmit() public {
        uint64 t0 = uint64(block.timestamp);
        wrapper.update(100e18, 0.5e18, TAU);

        // Fast forward 1 hour
        vm.warp(block.timestamp + 3600);

        // Remove old contribution and replace with new price
        wrapper.removeContribution(100e18, 0.5e18, t0, TAU);
        wrapper.update(200e18, 0.5e18, TAU);

        // Since it's the sole contributor, price should be exactly 200
        uint256 result = wrapper.getPrice();
        assertApproxEqRel(result, 200e18, 1e15, "Resubmitted price should replace old price");
    }

    // -- Time decay --

    function test_decay_fresh_submission_dominates() public {
        wrapper.update(100e18, 0.5e18, TAU);
        vm.warp(block.timestamp + 86400);
        wrapper.update(200e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice();
        assertGt(result, 150e18, "Fresh submission should pull price toward 200");
        assertLt(result, 200e18, "Old submission should still have some influence");
    }

    function test_decay_very_old_almost_zero() public {
        wrapper.update(100e18, 0.5e18, TAU);
        vm.warp(block.timestamp + 864000);
        wrapper.update(500e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice();
        assertApproxEqAbs(result, 500e18, 5e18, "Very old submission nearly irrelevant");
    }

    function test_decay_no_time_elapsed() public {
        wrapper.update(100e18, 0.5e18, TAU);
        wrapper.update(200e18, 0.5e18, TAU);

        uint256 result = wrapper.getPrice();
        assertApproxEqAbs(result, 150e18, 1e15, "No time elapsed -> no decay -> simple avg");
    }

    // -- Edge cases --

    function test_large_delta_t() public {
        wrapper.update(100e18, 0.5e18, TAU);
        vm.warp(block.timestamp + 365 days);
        wrapper.update(42e18, 0.1e18, TAU);

        uint256 result = wrapper.getPrice();
        assertApproxEqAbs(result, 42e18, 1e16, "After 1 year, old data fully decayed");
    }

    function test_many_submissions_different_times() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 3600);
            wrapper.update((100 + i * 10) * 1e18, 0.3e18, TAU);
        }

        uint256 result = wrapper.getPrice();
        assertGt(result, 100e18, "Should be above earliest price");
        assertLt(result, 150e18, "Should be below latest + margin");
    }

    // -- Fuzz tests --

    function testFuzz_single_submission_returns_exact(uint256 price, uint256 weight) public {
        price = bound(price, 1e15, 1e30);
        weight = bound(weight, 1e12, 0.5e18);

        wrapper.update(price, weight, TAU);

        uint256 result = wrapper.getPrice();
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

        uint256 result = wrapper.getPrice();
        assertGt(result, 0, "Price must always be positive");
    }

    function testFuzz_no_overflow(uint256 price, uint256 weight) public {
        price = bound(price, 1, 1e30);
        weight = bound(weight, 1, 0.5e18);

        wrapper.update(price, weight, TAU);
        wrapper.getPrice();
    }
}
