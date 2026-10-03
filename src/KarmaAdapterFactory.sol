// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Karma } from "./Karma.sol";

// Generic adapter factory interface.
interface IAdapterFactory {
    function createAdapter(bytes memory params) external returns (address adapter);
}

// Factory for deploying Karma oracle instances.
//
// Creates one Karma per (pool, tau, minBalance) configuration and caches it
// so later callers with the same config get the existing instance.
//
// Karma contracts are ownerless: all parameters are immutable at deploy time,
// so no ownership transfer is needed and there is no privileged admin.
contract KarmaAdapterFactory is IAdapterFactory {
    uint256 public constant DEFAULT_TAU = 124651;
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    mapping(bytes32 => address) public adapters;

    event KarmaCreated(
        address indexed pool,
        address indexed karma,
        uint256 tau,
        uint256 minBalance,
        string description
    );

    // Deploy or retrieve an adapter from encoded parameters.
    function createAdapter(bytes memory params) external override returns (address adapter) {
        (address pool, uint256 tau, uint256 minBalance, string memory desc) =
            abi.decode(params, (address, uint256, uint256, string));
        return _createKarma(pool, tau, minBalance, desc);
    }

    // Explicit parameters.
    function createKarma(address pool, uint256 tau, uint256 minBalance, string memory desc)
        external
        returns (address adapter)
    {
        return _createKarma(pool, tau, minBalance, desc);
    }

    // Default parameters.
    function createKarma(address pool, string memory desc) external returns (address adapter) {
        return _createKarma(pool, DEFAULT_TAU, DEFAULT_MIN_BALANCE, desc);
    }

    // Look up existing deployment.
    function getKarma(address pool, uint256 tau, uint256 minBalance)
        external
        view
        returns (address)
    {
        return adapters[_key(pool, tau, minBalance)];
    }

    function _createKarma(address pool, uint256 tau, uint256 minBalance, string memory desc)
        internal
        returns (address adapter)
    {
        bytes32 key = _key(pool, tau, minBalance);

        if (adapters[key] != address(0)) {
            return adapters[key];
        }

        Karma karma = new Karma(pool, tau, minBalance, desc);
        adapter = address(karma);
        adapters[key] = adapter;

        emit KarmaCreated(pool, adapter, tau, minBalance, desc);
    }

    function _key(address pool, uint256 tau, uint256 minBalance) internal pure returns (bytes32) {
        return keccak256(abi.encode(pool, tau, minBalance));
    }
}
