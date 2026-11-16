// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

// Extended oracle interface for Karma.
// Combines IOracle compatibility, Karma price submission, and
// Chainlink-compatible latestRoundData().
interface IKarmaOracle {
    // -- IOracle compatibility (PredictionPool integration) --

    // Current time-decayed weighted average price.
    function readValue() external view returns (uint256 value);

    // Returns (price, price) — Karma is a point-estimate oracle.
    function readValueInterval() external view returns (uint256 minValue, uint256 maxValue);

    // Timestamp of the most recent price submission.
    function lastUpdated() external view returns (uint256 timestamp);

    // Human-readable description of this oracle instance.
    function description() external view returns (string memory);

    // -- Karma-specific --

    // Lock bull/bear coins. Only locked coins give weight.
    function lock(uint256 bullAmount, uint256 bearAmount) external;

    // Unlock coins. This also removes the caller's submission.
    function unlock(uint256 bullAmount, uint256 bearAmount) external;

    // Coins an address has locked.
    function lockedBalances(address user)
        external
        view
        returns (uint256 bullAmount, uint256 bearAmount);

    // Submit a price observation; influence weighted by the neutrality of locked coins.
    // price must be WAD-scaled and > 0.
    function submitPrice(uint256 price) external;

    // Current neutrality weight of the coins an address has locked.
    function getWeight(address user) external view returns (uint256 weight);

    // Most recent submission by an address.
    function getSubmission(address user)
        external
        view
        returns (uint256 price, uint256 weight, uint256 timestamp);

    // -- Chainlink-compatible --

    // AggregatorV3-compatible view.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    // -- Events --

    // Emitted when an address locks or unlocks coins.
    event CoinsLocked(address indexed user, uint256 bullAmount, uint256 bearAmount);
    event CoinsUnlocked(address indexed user, uint256 bullAmount, uint256 bearAmount);

    // Emitted on every successful price submission.
    event PriceSubmitted(
        address indexed submitter, uint256 price, uint256 weight, uint256 timestamp
    );
}
