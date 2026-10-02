// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

/// @title IKarmaOracle — Extended oracle interface for Karma
/// @notice Combines IOracle compatibility, Karma price submission
///         functions, and a Chainlink-compatible latestRoundData() view.
interface IKarmaOracle {
    // ──────────────────────────────────────────────────────────────
    //  IOracle compatibility (PredictionPool integration)
    // ──────────────────────────────────────────────────────────────

    /// @notice Returns the current time-decayed weighted average price
    function readValue() external view returns (uint256 value);

    /// @notice Returns (price, price) — Karma is a point-estimate oracle
    function readValueInterval() external view returns (uint256 minValue, uint256 maxValue);

    /// @notice Timestamp of the most recent price submission
    function lastUpdated() external view returns (uint256 timestamp);

    /// @notice Human-readable description of this oracle instance
    function description() external view returns (string memory);

    // ──────────────────────────────────────────────────────────────
    //  Karma-specific
    // ──────────────────────────────────────────────────────────────

    /// @notice Submit a price observation; influence is weighted by neutrality
    /// @param price The submitted price (WAD-scaled, must be > 0)
    function submitPrice(uint256 price) external;

    /// @notice Compute the current neutrality weight for any address
    /// @param user The address to query
    /// @return weight Neutrality weight in [0, 0.5e18]
    function getWeight(address user) external view returns (uint256 weight);

    /// @notice Retrieve the most recent submission by an address
    /// @param user The address to query
    /// @return price     Submitted price (0 if never submitted)
    /// @return weight    Weight at time of submission
    /// @return timestamp Block timestamp of submission
    function getSubmission(address user)
        external
        view
        returns (uint256 price, uint256 weight, uint256 timestamp);

    // ──────────────────────────────────────────────────────────────
    //  Chainlink-compatible
    // ──────────────────────────────────────────────────────────────

    /// @notice Chainlink AggregatorV3-compatible view
    /// @return roundId         Submission counter
    /// @return answer          Current price as int256
    /// @return startedAt       First submission timestamp
    /// @return updatedAt       Most recent submission timestamp
    /// @return answeredInRound Same as roundId
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

    // ──────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────

    /// @notice Emitted on every successful price submission
    event PriceSubmitted(
        address indexed submitter, uint256 price, uint256 weight, uint256 timestamp
    );

    /// @notice Emitted when the minimum balance threshold is updated
    event MinBalanceUpdated(uint256 oldMin, uint256 newMin);
}
