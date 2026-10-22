// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { AccumulatorVault } from "../src/AccumulatorVault.sol";
import { PredictionPool } from "../src/PredictionPool.sol";
import { PredictionPoolFactory } from "../src/PredictionPoolFactory.sol";
import { ChainlinkAdapterFactory } from "../src/ChainlinkAdapterFactory.sol";
import { KarmaAdapterFactory } from "../src/KarmaAdapterFactory.sol";
import { Karma } from "../src/Karma.sol";

// DeployKarma — Foundry deployment script for Karma oracle system.
// Deploys the fee vault and protocol factories.
//
// Usage:
//   forge script script/DeployKarma.s.sol:DeployKarma \
//     --rpc-url $RPC_URL \
//     --broadcast \
//     --verify
//
// Environment variables:
//   DEV_ADDRESS      — Initial address allowed to manage the fee receiver.
//   DEV_FEE_RECEIVER — Initial destination for accumulated dev fees.
//   PREDICTION_POOL  — Existing pool (optional, to create a Karma instance).
//   TAU              — Decay time constant (optional, default 124651)
//   MIN_BALANCE      — Minimum balance threshold (optional, default 100e18)
//   DESCRIPTION      — Oracle description (optional)
contract DeployKarma is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address dev = vm.envAddress("DEV_ADDRESS");
        address devFeeReceiver = vm.envAddress("DEV_FEE_RECEIVER");
        address predictionPool = vm.envOr("PREDICTION_POOL", address(0));

        // Validate before broadcasting anything. A pool address is meaningful only
        // on the chain selected by RPC_URL, so require a live initialized pool there.
        if (predictionPool != address(0)) {
            _validatePredictionPool(predictionPool);
        }

        vm.startBroadcast(deployerKey);

        AccumulatorVault vault = new AccumulatorVault(dev, devFeeReceiver);
        console.log("AccumulatorVault deployed at:", address(vault));

        PredictionPoolFactory poolFactory = new PredictionPoolFactory(address(vault));
        console.log("PredictionPoolFactory deployed at:", address(poolFactory));
        console.log("CoinFactory deployed at:", address(poolFactory.coinFactory()));

        ChainlinkAdapterFactory chainlinkFactory = new ChainlinkAdapterFactory();
        console.log("ChainlinkAdapterFactory deployed at:", address(chainlinkFactory));

        KarmaAdapterFactory factory = new KarmaAdapterFactory();
        console.log("KarmaAdapterFactory deployed at:", address(factory));

        // 2. Optionally create a Karma instance
        if (predictionPool != address(0)) {
            uint256 _tau = vm.envOr("TAU", uint256(124651));
            uint256 _minBalance = vm.envOr("MIN_BALANCE", uint256(100e18));
            uint256 _minHoldBlocks = vm.envOr("MIN_HOLD_BLOCKS", uint256(1));
            string memory desc = vm.envOr("DESCRIPTION", string("Karma Oracle"));

            address karma = factory.createKarma(predictionPool, _tau, _minBalance, desc, _minHoldBlocks);
            console.log("Karma oracle deployed at:", karma);
            console.log("  Pool:", predictionPool);
            console.log("  Tau:", _tau);
            console.log("  Min Balance:", _minBalance);
            console.log("  Min Hold Blocks:", _minHoldBlocks);
        }

        vm.stopBroadcast();
    }

    function _validatePredictionPool(address poolAddress) private view {
        require(
            poolAddress.code.length > 0,
            "PREDICTION_POOL has no contract on RPC_URL's chain"
        );

        PredictionPool pool = PredictionPool(poolAddress);
        require(
            pool.initialized(),
            "PREDICTION_POOL is not an initialized pool on RPC_URL's chain"
        );
        require(
            address(pool.baseToken()).code.length > 0
                && address(pool.bullCoin()).code.length > 0
                && address(pool.bearCoin()).code.length > 0,
            "PREDICTION_POOL is not a valid initialized pool on RPC_URL's chain"
        );
    }
}
