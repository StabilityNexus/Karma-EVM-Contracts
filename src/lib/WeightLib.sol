// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

/// @title WeightLib — Neutrality weight for Karma oracle submissions
/// @notice Computes how "neutral" a user's bull/bear position is, producing a
///         weight equal to the user's balanced economic exposure.
///         A perfectly balanced user gets weight = normBull = normBear.
///         A one-sided holder gets weight = 0.
/// @dev    Adapted from Gluon's two-token weight calculation. Raw token balances
///         are normalized by coin price and the opposite reserve share so that
///         1 "normalized bullCoin" gives its holder exactly the same profit on an
///         upward move as 1 "normalized bearCoin" on a downward move.
///
///         Normalization (via reserve redistribution mechanism):
///           normBull = bullBalance × bullPrice × bearReserveShare
///           normBear = bearBalance × bearPrice × bullReserveShare
///
///         Then:
///           weight = min(normBull, normBear)
///
///         This ensures weight scales linearly with stake size:
///         Alice (1000/1000) gets 10× the weight of Bob (100/100).
library WeightLib {
    /// @notice Fixed-point scale factor (WAD)
    uint256 internal constant SCALE = 1e18;

    /// @notice Compute neutrality weight with full reserve normalization
    /// @param bullBalance  User's bullCoin balance (WAD)
    /// @param bearBalance  User's bearCoin balance (WAD)
    /// @param bullPrice    bullCoin price in base-token per coin (WAD-scaled, i.e. DENOMINATOR units)
    /// @param bearPrice    bearCoin price in base-token per coin (WAD-scaled, i.e. DENOMINATOR units)
    /// @param bullReserve  Total bull reserve in base tokens
    /// @param bearReserve  Total bear reserve in base tokens
    /// @return weight      Neutrality weight proportional to balanced stake
    function computeWeight(
        uint256 bullBalance,
        uint256 bearBalance,
        uint256 bullPrice,
        uint256 bearPrice,
        uint256 bullReserve,
        uint256 bearReserve
    ) internal pure returns (uint256 weight) {
        // If user has no position at all, weight is zero
        if (bullBalance == 0 && bearBalance == 0) return 0;

        uint256 totalReserve = bullReserve + bearReserve;
        if (totalReserve == 0) return 0;

        // Reserve shares (WAD-scaled)
        // bullReserveShare = bullReserve / totalReserve
        // bearReserveShare = bearReserve / totalReserve
        uint256 bearShare = (bearReserve * SCALE) / totalReserve;
        uint256 bullShare = (bullReserve * SCALE) / totalReserve;

        // Normalize: multiply balance by its coin price and the OPPOSITE reserve share.
        // This ensures that 1 normalized unit on each side represents equal profit potential.
        //
        // normBull = bullBalance × bullPrice × bearShare / SCALE
        // normBear = bearBalance × bearPrice × bullShare / SCALE
        //
        // We do two-step division to avoid overflow on large balances.
        uint256 normBull = (bullBalance * bullPrice) / SCALE;
        normBull = (normBull * bearShare) / SCALE;

        uint256 normBear = (bearBalance * bearPrice) / SCALE;
        normBear = (normBear * bullShare) / SCALE;

        // weight = min(normBull, normBear)
        // This scales linearly with stake: Alice (1000/1000) gets 10× Bob (100/100)
        weight = normBull < normBear ? normBull : normBear;
    }

    /// @notice Simplified weight for equal-reserve pools (50/50 reserve ratio)
    /// @dev    Equivalent to computeWeight when bullPrice == bearPrice and reserves are equal.
    ///         Useful for testing and documentation.
    /// @param bullBalance  User's bullCoin balance
    /// @param bearBalance  User's bearCoin balance
    /// @return weight      Neutrality weight proportional to balanced stake
    function computeWeightSimple(uint256 bullBalance, uint256 bearBalance)
        internal
        pure
        returns (uint256 weight)
    {
        if (bullBalance == 0 && bearBalance == 0) return 0;

        weight = bullBalance < bearBalance ? bullBalance : bearBalance;
    }
}
