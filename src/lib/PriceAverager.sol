// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { WadExp } from "./WadExp.sol";

// Time-decayed weighted price averaging for Karma.
//
// Maintains two decaying accumulators (weightedPrice and totalWeight) whose
// ratio gives the current consensus price. Each new submission decays the
// existing accumulators by exp(-dt/tau) before folding in the new value.
//
// Decay cancels in the ratio (numerator and denominator both multiplied by
// the same factor), so applying additional decay at read time is not needed.
library PriceAverager {
    uint256 internal constant WAD = 1e18;

    struct State {
        // Decayed accumulator of (price * weight) / WAD contributions
        uint256 weightedPrice;
        // Decayed accumulator of weight contributions
        uint256 totalWeight;
        // Timestamp of the last update (0 = no submissions yet)
        uint64 lastUpdateTime;
    }

    // Update the averager with a new (price, weight) contribution.
    // Removes the effect of elapsed time on the existing accumulators,
    // then adds the new contribution on top.
    function update(State storage self, uint256 price, uint256 weight, uint256 tau) internal {
        if (weight < 1) return;

        if (self.lastUpdateTime == 0) {
            // First submission - no prior data to decay.
            self.weightedPrice = (price * weight) / WAD;
            self.totalWeight = weight;
        } else {
            uint256 dt = block.timestamp - uint256(self.lastUpdateTime);
            uint256 decay = _decayFactor(dt, tau);

            // Decay existing accumulators then add new contribution.
            self.weightedPrice = (self.weightedPrice * decay) / WAD + (price * weight) / WAD;
            self.totalWeight = (self.totalWeight * decay) / WAD + weight;
        }

        self.lastUpdateTime = uint64(block.timestamp);
    }

    // Remove a prior contribution (used when the same account resubmits).
    // prevPrice and prevWeight are the stored values from the user's previous submission.
    // This is called before folding in the new submission so old entries do not accumulate.
    function removeContribution(
        State storage self,
        uint256 prevPrice,
        uint256 prevWeight,
        uint64 prevTimestamp,
        uint256 tau
    ) internal {
        if (prevWeight == 0 || prevTimestamp == 0 || self.lastUpdateTime == 0) {
            return;
        }

        // Bring accumulators up to current block.timestamp before subtracting.
        uint256 elapsed = block.timestamp - uint256(self.lastUpdateTime);
        if (elapsed > 0) {
            uint256 factor = _decayFactor(elapsed, tau);
            self.weightedPrice = (self.weightedPrice * factor) / WAD;
            self.totalWeight = (self.totalWeight * factor) / WAD;
            self.lastUpdateTime = uint64(block.timestamp);
        }

        // Decay the old contribution from when it was submitted to block.timestamp.
        uint256 dt = block.timestamp - uint256(prevTimestamp);
        uint256 decay = _decayFactor(dt, tau);
        uint256 prevWeightedPrice = (prevPrice * prevWeight) / WAD;
        uint256 decayedPrice = (prevWeightedPrice * decay) / WAD;
        uint256 decayedWeight = (prevWeight * decay) / WAD;

        // Subtract; clamp at zero to avoid underflow from rounding.
        if (self.totalWeight <= decayedWeight) {
            self.totalWeight = 0;
            self.weightedPrice = 0;
        } else {
            self.totalWeight -= decayedWeight;
            self.weightedPrice =
                self.weightedPrice > decayedPrice ? self.weightedPrice - decayedPrice : 0;
        }
    }

    // Current weighted average price. Returns 0 when no submissions exist
    // so downstream consumer pools do not revert on construction.
    function getPrice(State storage self) internal view returns (uint256 price) {
        if (self.lastUpdateTime == 0 || self.totalWeight == 0) return 0;
        // Decay cancels in numerator/denominator ratio - no read-time decay needed.
        price = (self.weightedPrice * WAD) / self.totalWeight;
    }

    // Backward-compatible overload accepting tau parameter.
    function getPrice(
        State storage self,
        uint256 /*tau*/
    )
        internal
        view
        returns (uint256 price)
    {
        return getPrice(self);
    }

    // True once at least one submission has been recorded.
    function hasPrice(State storage self) internal view returns (bool) {
        return self.lastUpdateTime > 0 && self.totalWeight > 0;
    }

    // exp(-dt / tau) in WAD. Returns WAD when dt == 0.
    function _decayFactor(uint256 dt, uint256 tau) internal pure returns (uint256 factor) {
        if (dt == 0) return WAD;

        int256 x = -int256((dt * WAD) / tau);
        int256 expResult = WadExp.expWad(x);

        if (expResult < 0) return 0;
        factor = uint256(expResult);
        if (factor > WAD) factor = WAD;
    }
}
