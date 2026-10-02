// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Karma } from "./Karma.sol";

// Generic adapter factory interface.
interface IAdapterFactory {
    function createAdapter(bytes memory params) external returns (address adapter);
}

// Factory for deploying Karma oracle instances.
//
// Creates Karma instances per PredictionPool configuration and caches them
// by configuration hash to prevent duplicate deployments. Ownership of each
// deployed Karma contract is transferred to the creator so they can adjust
// administrative parameters like minTotalBalance.
contract KarmaAdapterFactory is IAdapterFactory {
    uint256 public constant DEFAULT_TAU = 124651;
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    // Optional PredictionPoolFactory for backward-compatibility with oracle registries.
    address public immutable poolFactory;

    mapping(bytes32 => address) public adapters;

    event KarmaCreated(
        address indexed pool,
        address indexed karma,
        address indexed owner,
        uint256 tau,
        uint256 minBalance,
        string description
    );

    constructor(address _poolFactory) {
        poolFactory = _poolFactory;
    }

    // Deploy or retrieve an adapter from encoded parameters.
    function createAdapter(bytes memory params) external override returns (address adapter) {
        (address pool, uint256 tau, uint256 minBalance, string memory desc) =
            abi.decode(params, (address, uint256, uint256, string));
        return _createKarma(pool, tau, minBalance, desc, msg.sender);
    }

    // Explicit parameters with msg.sender as owner.
    function createKarma(address pool, uint256 tau, uint256 minBalance, string memory desc)
        external
        returns (address adapter)
    {
        return _createKarma(pool, tau, minBalance, desc, msg.sender);
    }

    // Explicit parameters specifying owner.
    function createKarma(
        address pool,
        uint256 tau,
        uint256 minBalance,
        string memory desc,
        address owner
    ) external returns (address adapter) {
        return _createKarma(pool, tau, minBalance, desc, owner);
    }

    // Default parameters with msg.sender as owner.
    function createKarma(address pool, string memory desc) external returns (address adapter) {
        return _createKarma(pool, DEFAULT_TAU, DEFAULT_MIN_BALANCE, desc, msg.sender);
    }

    // Look up existing deployment.
    function getKarma(address pool, uint256 tau, uint256 minBalance)
        external
        view
        returns (address)
    {
        return adapters[_key(pool, tau, minBalance)];
    }

    function _createKarma(
        address pool,
        uint256 tau,
        uint256 minBalance,
        string memory desc,
        address owner
    ) internal returns (address adapter) {
        bytes32 key = _key(pool, tau, minBalance);

        if (adapters[key] != address(0)) {
            return adapters[key];
        }

        Karma karma = new Karma(pool, tau, minBalance, desc);
        adapter = address(karma);
        adapters[key] = adapter;

        // Transfer ownership to the caller so they can manage oracle settings.
        if (owner != address(0) && owner != address(this)) {
            karma.transferOwnership(owner);
        }

        emit KarmaCreated(pool, adapter, owner, tau, minBalance, desc);
    }

    function _key(address pool, uint256 tau, uint256 minBalance) internal pure returns (bytes32) {
        return keccak256(abi.encode(pool, tau, minBalance));
    }
}
