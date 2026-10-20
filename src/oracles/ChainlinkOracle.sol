// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IOracle } from "../interfaces/IOracle.sol";
import { IAggregatorV3 } from "../interfaces/IAggregatorV3.sol";

contract ChainlinkOracle is IOracle {
    IAggregatorV3 public immutable priceFeed;
    uint8 public immutable feedDecimals;

    error InvalidPriceFeed();
    error InvalidPrice();
    error UnsupportedDecimals();

    constructor(address feed) {
        if (feed == address(0) || feed.code.length == 0) revert InvalidPriceFeed();
        priceFeed = IAggregatorV3(feed);
        uint8 decimals_ = IAggregatorV3(feed).decimals();
        if (decimals_ > 36) revert UnsupportedDecimals();
        feedDecimals = decimals_;
    }

    function readValue() public view override returns (uint256) {
        (, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        if (answer <= 0 || updatedAt == 0 || answeredInRound == 0) revert InvalidPrice();

        uint256 price = uint256(answer);
        if (feedDecimals <= 18) return price * 10 ** (18 - feedDecimals);
        return price / 10 ** (feedDecimals - 18);
    }

    function readValueInterval() external view override returns (uint256 minValue, uint256 maxValue) {
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
        uint256 scaled = uint256(answer);
        if (feedDecimals <= 18) scaled *= 10 ** (18 - feedDecimals);
        else scaled /= 10 ** (feedDecimals - 18);
        answer = int256(scaled);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
