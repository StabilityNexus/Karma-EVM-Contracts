// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { IAdapterFactory } from "./interfaces/IAdapterFactory.sol";

contract ChainlinkAdapterFactory is IAdapterFactory {
    uint256 public constant DEFAULT_MAX_STALENESS = 3600;

    mapping(bytes32 => address) public adapters;

    event AdapterCreated(address indexed priceFeed, address indexed adapter, uint256 maxStaleness);

    function createAdapter(bytes calldata params) external override returns (address adapter) {
        if (params.length > 32) {
            (address priceFeed_, uint256 staleness_) = abi.decode(params, (address, uint256));
            return _createAdapter(priceFeed_, staleness_);
        }
        return _createAdapter(abi.decode(params, (address)), DEFAULT_MAX_STALENESS);
    }

    function createAdapter(address priceFeed) external returns (address adapter) {
        return _createAdapter(priceFeed, DEFAULT_MAX_STALENESS);
    }

    function createAdapter(address priceFeed, uint256 maxStaleness) external returns (address adapter) {
        return _createAdapter(priceFeed, maxStaleness);
    }

    function getAdapter(address priceFeed, uint256 maxStaleness) external view returns (address) {
        return adapters[_key(priceFeed, maxStaleness)];
    }

    function _createAdapter(address priceFeed, uint256 maxStaleness) internal returns (address adapter) {
        uint256 effectiveStaleness = maxStaleness > 0 ? maxStaleness : DEFAULT_MAX_STALENESS;
        bytes32 key = _key(priceFeed, effectiveStaleness);
        adapter = adapters[key];
        if (adapter != address(0)) return adapter;
        adapter = address(new ChainlinkOracle(priceFeed, effectiveStaleness));
        adapters[key] = adapter;
        emit AdapterCreated(priceFeed, adapter, effectiveStaleness);
    }

    function _key(address priceFeed, uint256 maxStaleness) internal pure returns (bytes32) {
        return keccak256(abi.encode(priceFeed, maxStaleness));
    }
}
