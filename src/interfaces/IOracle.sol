// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

interface IOracle {
    function readValue() external view returns (uint256 value);
    function readValueInterval() external view returns (uint256 minValue, uint256 maxValue);
    function lastUpdated() external view returns (uint256 timestamp);
    function description() external view returns (string memory);
}
