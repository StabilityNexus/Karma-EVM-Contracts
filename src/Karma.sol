// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IOracle } from "./interfaces/IOracle.sol";
import { IKarmaOracle } from "./interfaces/IKarmaOracle.sol";
import { WeightLib } from "./lib/WeightLib.sol";
import { PriceAverager } from "./lib/PriceAverager.sol";

// Minimal read interface for PredictionPool.
interface IPredictionPoolReader {
    function baseToken() external view returns (IERC20);
    function bullCoin() external view returns (address);
    function bearCoin() external view returns (address);
}

// Minimal read interface for Coin price queries.
interface ICoinReader {
    function priceSell() external view returns (uint256);
}

// Permissionless on-chain price-discovery oracle.
//
// Participants submit price observations weighted by the economic neutrality
// of their bull/bear holdings. Equal economic exposure to up/down moves gives
// maximum weight; one-sided holdings give zero weight. Older submissions decay
// exponentially so the oracle tracks fresh consensus.
contract Karma is IOracle, IKarmaOracle, Ownable, ReentrancyGuard {
    using PriceAverager for PriceAverager.State;

    uint256 public constant SCALE = 1e18;
    uint256 public constant COIN_DENOMINATOR = 100_000;
    uint256 public constant DEFAULT_TAU = 124651;
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    IPredictionPoolReader public immutable pool;
    IERC20 public immutable baseToken;
    address public immutable bullCoin;
    address public immutable bearCoin;
    uint256 public immutable tau;

    string private _description;
    uint256 public minTotalBalance;
    PriceAverager.State private _averager;
    uint256 public submissionCount;
    uint256 public firstSubmissionTime;

    struct Submission {
        uint256 price;
        uint256 weight;
        uint256 timestamp;
    }

    mapping(address => Submission) public submissions;

    error ZeroPrice();
    error InsufficientBalance(uint256 totalBalance, uint256 minRequired);
    error ZeroWeight();
    error InvalidPool();
    error InvalidTau();

    constructor(address _pool, uint256 _tau, uint256 _minTotalBalance, string memory desc)
        Ownable(msg.sender)
    {
        if (_pool == address(0)) revert InvalidPool();

        pool = IPredictionPoolReader(_pool);
        baseToken = pool.baseToken();
        bullCoin = pool.bullCoin();
        bearCoin = pool.bearCoin();

        tau = _tau > 0 ? _tau : DEFAULT_TAU;
        minTotalBalance = _minTotalBalance > 0 ? _minTotalBalance : DEFAULT_MIN_BALANCE;
        _description = desc;
    }

    // --- IOracle implementation ---

    function readValue() public view override(IOracle, IKarmaOracle) returns (uint256 value) {
        return _averager.getPrice();
    }

    function readValueInterval()
        external
        view
        override(IOracle, IKarmaOracle)
        returns (uint256 minValue, uint256 maxValue)
    {
        uint256 price = readValue();
        return (price, price);
    }

    function lastUpdated()
        external
        view
        override(IOracle, IKarmaOracle)
        returns (uint256 timestamp)
    {
        return uint256(_averager.lastUpdateTime);
    }

    function description() external view override(IOracle, IKarmaOracle) returns (string memory) {
        return _description;
    }

    // --- Price submission ---

    function submitPrice(uint256 price) external override nonReentrant {
        if (price == 0) revert ZeroPrice();

        uint256 bullBalance = IERC20(bullCoin).balanceOf(msg.sender);
        uint256 bearBalance = IERC20(bearCoin).balanceOf(msg.sender);

        uint256 totalBalance = bullBalance + bearBalance;
        if (totalBalance < minTotalBalance) {
            revert InsufficientBalance(totalBalance, minTotalBalance);
        }

        uint256 bullPrice = ICoinReader(bullCoin).priceSell();
        uint256 bearPrice = ICoinReader(bearCoin).priceSell();
        uint256 bullReserve = baseToken.balanceOf(bullCoin);
        uint256 bearReserve = baseToken.balanceOf(bearCoin);

        uint256 weight = WeightLib.computeWeight(
            bullBalance, bearBalance, bullPrice, bearPrice, bullReserve, bearReserve
        );

        if (weight < 1) revert ZeroWeight();

        // If user submitted previously, remove their old decayed contribution
        // before adding the new one so repeated submissions do not accumulate.
        Submission storage prevSub = submissions[msg.sender];
        if (prevSub.timestamp > 0) {
            _averager.removeContribution(
                prevSub.price, prevSub.weight, uint64(prevSub.timestamp), tau
            );
        }

        // Add new submission to the time-decayed averager.
        _averager.update(price, weight, tau);

        submissions[msg.sender] =
            Submission({ price: price, weight: weight, timestamp: block.timestamp });

        submissionCount++;
        if (submissionCount == 1) {
            firstSubmissionTime = block.timestamp;
        }

        emit PriceSubmitted(msg.sender, price, weight, block.timestamp);
    }

    // --- Queries ---

    function getWeight(address user) external view override returns (uint256 weight) {
        uint256 bullBalance = IERC20(bullCoin).balanceOf(user);
        uint256 bearBalance = IERC20(bearCoin).balanceOf(user);

        uint256 bullPrice = ICoinReader(bullCoin).priceSell();
        uint256 bearPrice = ICoinReader(bearCoin).priceSell();
        uint256 bullReserve = baseToken.balanceOf(bullCoin);
        uint256 bearReserve = baseToken.balanceOf(bearCoin);

        weight = WeightLib.computeWeight(
            bullBalance, bearBalance, bullPrice, bearPrice, bullReserve, bearReserve
        );
    }

    function getSubmission(address user)
        external
        view
        override
        returns (uint256 price, uint256 weight, uint256 timestamp)
    {
        Submission storage sub = submissions[user];
        return (sub.price, sub.weight, sub.timestamp);
    }

    function hasPrice() external view returns (bool) {
        return _averager.hasPrice();
    }

    // --- Chainlink-compatible feed interface ---

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 price = readValue();
        uint256 count = submissionCount;

        roundId = uint80(count);
        answer = int256(price);
        startedAt = firstSubmissionTime;
        updatedAt = uint256(_averager.lastUpdateTime);
        answeredInRound = uint80(count);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    // --- Admin ---

    function setMinTotalBalance(uint256 newMinBalance) external onlyOwner {
        uint256 oldMin = minTotalBalance;
        minTotalBalance = newMinBalance;
        emit MinBalanceUpdated(oldMin, newMinBalance);
    }
}
