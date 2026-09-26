// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import {Karma} from "./Karma.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @title IOracleRegistrar — Minimal interface for PredictionPoolFactory.registerOracle
interface IOracleRegistrar {
    function registerOracle(address oracle) external;
}

/// @title IAdapterFactory — Generic adapter factory interface (matches Fate)
interface IAdapterFactory {
    function createAdapter(bytes memory params) external returns (address adapter);
}

/// @title KarmaAdapterFactory — Creates Karma oracle instances for PredictionPool integration
/// @notice Follows the same factory + registry pattern as Fate's ChainlinkAdapterFactory
///         and FateAdapterFactory. Creates Karma instances, registers them as valid oracles
///         on the PredictionPoolFactory, and caches them to prevent duplicates.
/// @dev    The factory key is hash(pool, tau, minBalance) to allow different configurations
///         per pool while preventing duplicate deployments.
contract KarmaAdapterFactory is IAdapterFactory {
    /// @notice Default decay time constant (~1-day EWMA half-life)
    uint256 public constant DEFAULT_TAU = 124651;

    /// @notice Default minimum balance for Sybil resistance
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    /// @notice PredictionPoolFactory address for oracle registration
    address public immutable poolFactory;

    /// @notice Deployed Karma instances keyed by configuration hash
    mapping(bytes32 => address) public adapters;

    event KarmaCreated(
        address indexed pool,
        address indexed karma,
        uint256 tau,
        uint256 minBalance,
        string description
    );

    error InvalidPoolFactory();

    constructor(address _poolFactory) {
        if (_poolFactory == address(0)) revert InvalidPoolFactory();
        poolFactory = _poolFactory;
    }

    /// @notice IAdapterFactory implementation — creates Karma from encoded params
    /// @param params ABI-encoded (address pool, uint256 tau, uint256 minBalance, string description)
    function createAdapter(bytes memory params) external override returns (address adapter) {
        (address pool, uint256 _tau, uint256 _minBalance, string memory desc) =
            abi.decode(params, (address, uint256, uint256, string));
        return _createKarma(pool, _tau, _minBalance, desc);
    }

    /// @notice Explicit-parameter convenience function
    function createKarma(
        address pool,
        uint256 _tau,
        uint256 _minBalance,
        string memory desc
    ) external returns (address adapter) {
        return _createKarma(pool, _tau, _minBalance, desc);
    }

    /// @notice Create with defaults (tau = DEFAULT_TAU, minBalance = DEFAULT_MIN_BALANCE)
    function createKarma(address pool, string memory desc) external returns (address adapter) {
        return _createKarma(pool, DEFAULT_TAU, DEFAULT_MIN_BALANCE, desc);
    }

    /// @notice Look up an existing Karma deployment by its configuration
    function getKarma(
        address pool,
        uint256 _tau,
        uint256 _minBalance
    ) external view returns (address) {
        return adapters[_key(pool, _tau, _minBalance)];
    }

    // ──────────────────────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────────────────────

    function _createKarma(
        address pool,
        uint256 _tau,
        uint256 _minBalance,
        string memory desc
    ) internal returns (address adapter) {
        bytes32 key = _key(pool, _tau, _minBalance);

        // Return existing if already deployed
        if (adapters[key] != address(0)) {
            return adapters[key];
        }

        // Deploy new Karma
        Karma karma = new Karma(pool, _tau, _minBalance, desc);
        adapter = address(karma);
        adapters[key] = adapter;

        // Register as valid oracle on the PredictionPoolFactory
        IOracleRegistrar(poolFactory).registerOracle(adapter);

        emit KarmaCreated(pool, adapter, _tau, _minBalance, desc);
    }

    function _key(
        address pool,
        uint256 _tau,
        uint256 _minBalance
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(pool, _tau, _minBalance));
    }
}
