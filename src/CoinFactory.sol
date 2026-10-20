// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Coin, CoinConfig } from "./Coin.sol";

contract CoinFactory {
    error OnlyPredictionPool();

    function createCoin(bytes calldata encodedConfig) external returns (address) {
        CoinConfig memory config = abi.decode(encodedConfig, (CoinConfig));
        if (msg.sender != config.predictionPool) revert OnlyPredictionPool();
        return address(new Coin(config));
    }
}
