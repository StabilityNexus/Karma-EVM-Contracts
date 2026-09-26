// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {KarmaAdapterFactory} from "../src/KarmaAdapterFactory.sol";
import {Karma} from "../src/Karma.sol";

/// @title DeployKarma — Foundry deployment script for Karma oracle system
/// @notice Deploys the KarmaAdapterFactory and optionally creates a Karma instance
///         for an existing PredictionPool.
///
///         Usage:
///           forge script script/DeployKarma.s.sol:DeployKarma \
///             --rpc-url $RPC_URL \
///             --broadcast \
///             --verify
///
///         Environment variables:
///           POOL_FACTORY     — PredictionPoolFactory address (required)
///           PREDICTION_POOL  — PredictionPool address (optional, to create Karma instance)
///           TAU              — Decay time constant (optional, default 124651)
///           MIN_BALANCE      — Minimum balance threshold (optional, default 100e18)
///           DESCRIPTION      — Oracle description (optional)
contract DeployKarma is Script {
    function run() external {
        address poolFactory = vm.envAddress("POOL_FACTORY");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // ── 1. Deploy KarmaAdapterFactory ────────────────────────
        KarmaAdapterFactory factory = new KarmaAdapterFactory(poolFactory);
        console.log("KarmaAdapterFactory deployed at:", address(factory));

        // ── 2. Optionally create a Karma instance ────────────────
        address predictionPool = vm.envOr("PREDICTION_POOL", address(0));
        if (predictionPool != address(0)) {
            uint256 _tau = vm.envOr("TAU", uint256(124651));
            uint256 _minBalance = vm.envOr("MIN_BALANCE", uint256(100e18));
            string memory desc = vm.envOr("DESCRIPTION", string("Karma Oracle"));

            address karma = factory.createKarma(predictionPool, _tau, _minBalance, desc);
            console.log("Karma oracle deployed at:", karma);
            console.log("  Pool:", predictionPool);
            console.log("  Tau:", _tau);
            console.log("  Min Balance:", _minBalance);
        }

        vm.stopBroadcast();
    }
}
