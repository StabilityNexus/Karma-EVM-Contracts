// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Karma } from "./Karma.sol";
import { IAdapterFactory } from "./interfaces/IAdapterFactory.sol";

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
    uint256 public constant DEFAULT_MIN_HOLD_BLOCKS = 1;

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
        (address pool, uint256 tau, uint256 minBalance, string memory desc, uint256 minHoldBlocks) =
            abi.decode(params, (address, uint256, uint256, string, uint256));
        return _createKarma(pool, tau, minBalance, desc, minHoldBlocks);
    }

    // Explicit parameters.
    function createKarma(
        address pool,
        uint256 tau,
        uint256 minBalance,
        string memory desc,
        uint256 minHoldBlocks
    ) external returns (address adapter) {
        return _createKarma(pool, tau, minBalance, desc, minHoldBlocks);
    }

    // Default parameters.
    function createKarma(address pool, string memory desc) external returns (address adapter) {
        return _createKarma(pool, DEFAULT_TAU, DEFAULT_MIN_BALANCE, desc, DEFAULT_MIN_HOLD_BLOCKS);
    }

    // Look up existing deployment.
    function getKarma(address pool, uint256 tau, uint256 minBalance, uint256 minHoldBlocks)
        external
        view
        returns (address)
    {
        return adapters[_key(pool, tau, minBalance, minHoldBlocks)];
    }

    function _createKarma(
        address pool,
        uint256 tau,
        uint256 minBalance,
        string memory desc,
        uint256 minHoldBlocks
    ) internal returns (address adapter) {
        uint256 effectiveTau = tau > 0 ? tau : DEFAULT_TAU;
        uint256 effectiveMinBalance = minBalance > 0 ? minBalance : DEFAULT_MIN_BALANCE;
        uint256 effectiveMinHoldBlocks = minHoldBlocks > 0 ? minHoldBlocks : DEFAULT_MIN_HOLD_BLOCKS;
        bytes32 key = _key(pool, effectiveTau, effectiveMinBalance, effectiveMinHoldBlocks);

        if (adapters[key] != address(0)) {
            return adapters[key];
        }

        Karma karma =
            new Karma(pool, effectiveTau, effectiveMinBalance, desc, effectiveMinHoldBlocks);
        adapter = address(karma);
        adapters[key] = adapter;

        emit KarmaCreated(pool, adapter, effectiveTau, effectiveMinBalance, desc);
    }

    function _key(address pool, uint256 tau, uint256 minBalance, uint256 minHoldBlocks)
        internal
        pure
        returns (bytes32)
    {
        uint256 effectiveTau = tau > 0 ? tau : DEFAULT_TAU;
        uint256 effectiveMinBalance = minBalance > 0 ? minBalance : DEFAULT_MIN_BALANCE;
        uint256 effectiveMinHoldBlocks = minHoldBlocks > 0 ? minHoldBlocks : DEFAULT_MIN_HOLD_BLOCKS;
        return
            keccak256(abi.encode(pool, effectiveTau, effectiveMinBalance, effectiveMinHoldBlocks));
    }
}
