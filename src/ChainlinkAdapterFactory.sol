// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { ChainlinkOracle } from "./oracles/ChainlinkOracle.sol";
import { IAdapterFactory } from "./interfaces/IAdapterFactory.sol";

contract ChainlinkAdapterFactory is IAdapterFactory {
    mapping(address => address) public priceFeedToAdapter;

    event AdapterCreated(address indexed priceFeed, address indexed adapter);

    function createAdapter(bytes calldata params) external override returns (address adapter) {
        address priceFeed = abi.decode(params, (address));
        return _createAdapter(priceFeed);
    }

    function createAdapter(address priceFeed) external returns (address adapter) {
        return _createAdapter(priceFeed);
    }

    function getAdapter(address priceFeed) external view returns (address) {
        return priceFeedToAdapter[priceFeed];
    }

    function _createAdapter(address priceFeed) internal returns (address adapter) {
        adapter = priceFeedToAdapter[priceFeed];
        if (adapter != address(0)) return adapter;
        adapter = address(new ChainlinkOracle(priceFeed));
        priceFeedToAdapter[priceFeed] = adapter;
        emit AdapterCreated(priceFeed, adapter);
    }
}
