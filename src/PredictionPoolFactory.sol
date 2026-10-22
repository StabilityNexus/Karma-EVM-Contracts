// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PredictionPool, PredictionPoolConfig } from "./PredictionPool.sol";
import { CoinFactory } from "./CoinFactory.sol";
import { IOracle } from "./interfaces/IOracle.sol";

contract PredictionPoolFactory {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 100_000;
    address public immutable accumulatorVault;
    CoinFactory public immutable coinFactory;

    address[] public allPools;
    mapping(address => address[]) public poolsByCreator;

    error InvalidAddress();
    error InvalidOracle();
    error InvalidFeeConfiguration();

    event PoolCreated(
        address indexed pool,
        address indexed bullCoin,
        address indexed bearCoin,
        address creator,
        address oracle
    );

    constructor(address accumulatorVault_) {
        if (accumulatorVault_ == address(0)) revert InvalidAddress();
        accumulatorVault = accumulatorVault_;
        coinFactory = new CoinFactory();
    }

    function createPool(PredictionPoolConfig memory config) external returns (address pool) {
        config.vaultCreator = msg.sender;
        config.accumulatorVault = accumulatorVault;
        config.coinFactory = address(coinFactory);
        return _createPool(config);
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    function _createPool(PredictionPoolConfig memory config) internal returns (address pool) {
        if (config.baseToken == address(0)) revert InvalidAddress();
        _checkOracle(config.oracle);
        if (
            config.mintFee + config.creatorFee + config.devFee > DENOMINATOR
                || config.burnFee + config.creatorFee + config.devFee > DENOMINATOR
        ) revert InvalidFeeConfiguration();

        PredictionPool newPool = new PredictionPool(config.vaultCreator, abi.encode(config));

        IERC20 token = IERC20(config.baseToken);
        if (config.initialDeposit > 0) {
            token.safeTransferFrom(msg.sender, address(this), config.initialDeposit);
        }
        token.forceApprove(address(newPool), config.initialDeposit);
        newPool.initialize(config.initialDeposit);
        token.forceApprove(address(newPool), 0);

        pool = address(newPool);
        allPools.push(pool);
        poolsByCreator[msg.sender].push(pool);
        emit PoolCreated(
            pool,
            address(newPool.bullCoin()),
            address(newPool.bearCoin()),
            msg.sender,
            config.oracle
        );
    }

    function _checkOracle(address oracle) internal view {
        if (oracle == address(0) || oracle.code.length == 0) revert InvalidOracle();
        try IOracle(oracle).readValue() returns (uint256) { }
        catch {
            revert InvalidOracle();
        }
    }
}
