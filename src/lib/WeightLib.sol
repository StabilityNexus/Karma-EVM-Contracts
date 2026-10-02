// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

// Neutrality weight for Karma oracle submissions.
//
// Weight = min(normalizedBull, normalizedBear)
//
// Normalized exposures (from pool reserve-redistribution math):
//   normalizedBull = bullBalance × bullPrice × bearReserveShare
//   normalizedBear = bearBalance × bearPrice × bullReserveShare
//
// where bearReserveShare = bearReserve / totalReserve (and vice-versa).
//
// Using plain min() — no denominator — so Alice (1000/1000) gets exactly 10×
// the weight of Bob (100/100). A purely one-sided holder gets weight = 0.
//
// priceSell() returns values in COIN_DENOMINATOR (100_000) units, not WAD,
// so the two-step division below avoids phantom 1e18 scaling.
library WeightLib {
    uint256 internal constant COIN_DENOMINATOR = 100_000;

    // Full weight using on-chain reserve data.
    // bullPrice / bearPrice come from Coin.priceSell() — units: COIN_DENOMINATOR per coin (WAD).
    // bullReserve / bearReserve are raw baseToken amounts held by each Coin contract.
    function computeWeight(
        uint256 bullBalance,
        uint256 bearBalance,
        uint256 bullPrice,
        uint256 bearPrice,
        uint256 bullReserve,
        uint256 bearReserve
    ) internal pure returns (uint256 weight) {
        if (bullBalance == 0 && bearBalance == 0) return 0;

        uint256 totalReserve = bullReserve + bearReserve;
        if (totalReserve == 0) return 0;

        // Reserve shares as fractions of totalReserve (integer arithmetic, no WAD).
        // normBull = bullBalance × bullPrice × bearReserve / (COIN_DENOMINATOR × totalReserve)
        // Two-step to avoid overflow on large balances × prices.
        uint256 normBull = (bullBalance * bullPrice) / COIN_DENOMINATOR;
        normBull = (normBull * bearReserve) / totalReserve;

        uint256 normBear = (bearBalance * bearPrice) / COIN_DENOMINATOR;
        normBear = (normBear * bullReserve) / totalReserve;

        // weight = min(normBull, normBear) — no denominator; magnitude is preserved.
        weight = normBull < normBear ? normBull : normBear;
    }

    // Simplified weight for equal-reserve pools (50/50 split).
    // Equivalent to computeWeight when bullPrice == bearPrice and reserves are equal.
    // Useful for testing and documentation.
    function computeWeightSimple(uint256 bullBalance, uint256 bearBalance)
        internal
        pure
        returns (uint256 weight)
    {
        if (bullBalance == 0 && bearBalance == 0) return 0;
        weight = bullBalance < bearBalance ? bullBalance : bearBalance;
    }
}
