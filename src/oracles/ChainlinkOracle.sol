// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IOracle } from "../interfaces/IOracle.sol";
import { IAggregatorV3 } from "../interfaces/IAggregatorV3.sol";

contract ChainlinkOracle is IOracle {
    IAggregatorV3 public immutable priceFeed;
    uint8 public immutable feedDecimals;
    uint256 public immutable maxStaleness;

    error InvalidPriceFeed();
    error InvalidPrice();
    error StalePrice();
    error UnsupportedDecimals();

    constructor(address feed, uint256 _maxStaleness) {
        if (feed == address(0) || feed.code.length == 0) revert InvalidPriceFeed();
        priceFeed = IAggregatorV3(feed);
        uint8 decimals_ = IAggregatorV3(feed).decimals();
        if (decimals_ > 36) revert UnsupportedDecimals();
        feedDecimals = decimals_;
        maxStaleness = _maxStaleness > 0 ? _maxStaleness : 3600;
    }

    function readValue() public view override returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        if (answer <= 0 || updatedAt == 0 || answeredInRound == 0) revert InvalidPrice();
        if (answeredInRound < roundId) revert StalePrice();
        if (block.timestamp - updatedAt > maxStaleness) revert StalePrice();

        uint256 price = uint256(answer);
        if (feedDecimals <= 18) return price * 10 ** (18 - feedDecimals);
        return price / 10 ** (feedDecimals - 18);
    }

    function readValueInterval()
        external
        view
        override
        returns (uint256 minValue, uint256 maxValue)
    {
        uint256 price = readValue();
        return (price, price);
    }

    function lastUpdated() external view override returns (uint256) {
        (,,, uint256 updatedAt,) = priceFeed.latestRoundData();
        return updatedAt;
    }

    function description() external view override returns (string memory) {
        return priceFeed.description();
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (answeredInRound < roundId) revert StalePrice();
        if (block.timestamp - updatedAt > maxStaleness) revert StalePrice();
        if (feedDecimals <= 18) {
            answer = int256(uint256(answer) * 10 ** (18 - feedDecimals));
        } else {
            answer = int256(uint256(answer) / 10 ** (feedDecimals - 18));
        }
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
