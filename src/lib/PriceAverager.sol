// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { WadExp } from "./WadExp.sol";

/// @title PriceAverager — Time-decayed weighted price averaging for Karma
/// @notice Maintains a running weighted average of submitted prices where older
///         contributions decay exponentially over time. Reuses the EWMA step
///         formula (ewma + alpha*(s - ewma) where
///         alpha = 1 - exp(-dt/tau)).
/// @dev    Instead of tracking a single EWMA signal, this tracks two parallel
///         decaying accumulators (weightedPrice and totalWeight) whose ratio
///         gives the current consensus price.
library PriceAverager {
    uint256 internal constant WAD = 1e18;

    struct State {
        /// @notice Decayed accumulator of (price × weight) contributions
        uint256 weightedPrice;
        /// @notice Decayed accumulator of weight contributions
        uint256 totalWeight;
        /// @notice Timestamp of the last update (0 = no submissions yet)
        uint64 lastUpdateTime;
    }

    /// @notice Update the price averager with a new submission
    /// @dev    Applies exponential decay to existing accumulators, then adds the
    ///         new (price, weight) contribution. The decay factor is computed as
    ///         exp(-dt/tau) via WadExp, matching continuous EWMA decay.
    /// @param self   The averager state (storage)
    /// @param price  The submitted price (WAD-scaled)
    /// @param weight The submitter's neutrality weight (WAD-scaled, max 0.5e18)
    /// @param tau    Decay time constant in seconds (larger = slower decay)
    function update(State storage self, uint256 price, uint256 weight, uint256 tau) internal {
        if (weight == 0) return;

        if (self.lastUpdateTime == 0) {
            // First submission — no decay needed
            self.weightedPrice = (price * weight) / WAD;
            self.totalWeight = weight;
        } else {
            uint256 dt = block.timestamp - uint256(self.lastUpdateTime);
            uint256 decay = _decayFactor(dt, tau);

            // Decay existing accumulators
            uint256 decayedWP = (self.weightedPrice * decay) / WAD;
            uint256 decayedTW = (self.totalWeight * decay) / WAD;

            // Add new contribution
            self.weightedPrice = decayedWP + (price * weight) / WAD;
            self.totalWeight = decayedTW + weight;
        }

        self.lastUpdateTime = uint64(block.timestamp);
    }

    /// @notice Read the current time-decayed weighted average price
    /// @dev    Applies decay to the stored accumulators without writing, then
    ///         returns the ratio. Reverts if no submissions exist.
    /// @param self The averager state (storage, read-only)
    /// @param tau  Decay time constant in seconds
    /// @return price The current weighted average price (WAD-scaled)
    function getPrice(State storage self, uint256 tau) internal view returns (uint256 price) {
        require(self.lastUpdateTime > 0, "No price available");

        uint256 dt = block.timestamp - uint256(self.lastUpdateTime);
        uint256 decay = _decayFactor(dt, tau);

        uint256 decayedWP = (self.weightedPrice * decay) / WAD;
        uint256 decayedTW = (self.totalWeight * decay) / WAD;

        require(decayedTW > 0, "Total weight decayed to zero");

        price = (decayedWP * WAD) / decayedTW;
    }

    /// @notice Check whether the averager has received at least one submission
    function hasPrice(State storage self) internal view returns (bool) {
        return self.lastUpdateTime > 0 && self.totalWeight > 0;
    }

    /// @notice Compute the exponential decay factor for a given time delta
    /// @dev    decay = exp(-dt / tau), matching continuous EWMA decay.
    ///         Returns WAD (1e18) when dt == 0 (no decay).
    /// @param dt   Seconds since last update
    /// @param tau  Decay time constant
    /// @return factor Decay factor in [0, WAD]
    function _decayFactor(uint256 dt, uint256 tau) internal pure returns (uint256 factor) {
        if (dt == 0) return WAD;

        // x = -dt/tau in WAD
        int256 x = -int256((dt * WAD) / tau);

        // exp(x) via WadExp — fixed-point exponential calculation
        int256 expResult = WadExp.expWad(x);

        // Clamp to [0, WAD] — exp of a negative number is in (0, 1]
        if (expResult < 0) return 0;
        factor = uint256(expResult);
        if (factor > WAD) factor = WAD;
    }
}
