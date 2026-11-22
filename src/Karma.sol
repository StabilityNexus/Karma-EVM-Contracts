// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
// Participants lock bull/bear coins here and submit price observations weighted
// by the economic neutrality of the locked coins. Unlocking removes the
// submission, so the same coins never back two submissions at once. Equal
// economic exposure to up/down moves gives maximum weight; one-sided holdings
// give zero weight. Older submissions decay
// exponentially so the oracle tracks fresh consensus.
//
// All configuration is immutable. The factory caches instances by
// (pool, tau, minTotalBalance) so every consumer sharing a config key
// gets the same oracle — no owner can change the rules after deployment.
contract Karma is IOracle, IKarmaOracle, ReentrancyGuard {
    using PriceAverager for PriceAverager.State;
    using SafeERC20 for IERC20;

    uint256 public constant DEFAULT_TAU = 124651;
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    IPredictionPoolReader public immutable pool;
    IERC20 public immutable baseToken;
    address public immutable bullCoin;
    address public immutable bearCoin;
    uint256 public immutable tau;
    uint256 public immutable minTotalBalance;

    string private _description;
    PriceAverager.State private _averager;
    uint256 public submissionCount;
    uint256 public firstSubmissionTime;
    uint256 public lastSubmissionTime;
    uint256 public activeSubmissions;

    struct Submission {
        uint256 price;
        uint256 weight;
        uint256 timestamp;
    }

    mapping(address => Submission) public submissions;
    mapping(address => uint256) private lockedBull;
    mapping(address => uint256) private lockedBear;

    error ZeroPrice();
    error InsufficientBalance(uint256 totalBalance, uint256 minRequired);
    error ZeroWeight();
    error InvalidPool();
    error InsufficientLocked();

    constructor(address _pool, uint256 _tau, uint256 _minTotalBalance, string memory desc) {
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
        return lastSubmissionTime;
    }

    function description() external view override(IOracle, IKarmaOracle) returns (string memory) {
        return _description;
    }

    // --- Locking ---

    // Coins only give weight while they are locked here.
    function lock(uint256 bullAmount, uint256 bearAmount) external override nonReentrant {
        lockedBull[msg.sender] += bullAmount;
        lockedBear[msg.sender] += bearAmount;
        if (bullAmount > 0) {
            IERC20(bullCoin).safeTransferFrom(msg.sender, address(this), bullAmount);
        }
        if (bearAmount > 0) {
            IERC20(bearCoin).safeTransferFrom(msg.sender, address(this), bearAmount);
        }
        emit CoinsLocked(msg.sender, bullAmount, bearAmount);
    }

    // Unlocking removes the caller's submission, so the coins cannot back another one.
    function unlock(uint256 bullAmount, uint256 bearAmount) external override nonReentrant {
        if (bullAmount > lockedBull[msg.sender] || bearAmount > lockedBear[msg.sender]) {
            revert InsufficientLocked();
        }

        Submission storage sub = submissions[msg.sender];
        if (sub.timestamp > 0) {
            _averager.removeContribution(sub.price, sub.weight, uint64(sub.timestamp), tau);
            delete submissions[msg.sender];
            // Rounding can leave a few wei behind. With no submissions left, clear them so they
            // do not turn into a price.
            if (--activeSubmissions == 0) {
                _averager.weightedPrice = 0;
                _averager.totalWeight = 0;
            }
        }

        lockedBull[msg.sender] -= bullAmount;
        lockedBear[msg.sender] -= bearAmount;
        if (bullAmount > 0) IERC20(bullCoin).safeTransfer(msg.sender, bullAmount);
        if (bearAmount > 0) IERC20(bearCoin).safeTransfer(msg.sender, bearAmount);
        emit CoinsUnlocked(msg.sender, bullAmount, bearAmount);
    }

    function lockedBalances(address user)
        external
        view
        override
        returns (uint256 bullAmount, uint256 bearAmount)
    {
        return (lockedBull[user], lockedBear[user]);
    }

    // --- Price submission ---

    function submitPrice(uint256 price) external override nonReentrant {
        if (price == 0) revert ZeroPrice();

        uint256 bullBalance = lockedBull[msg.sender];
        uint256 bearBalance = lockedBear[msg.sender];

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
        } else {
            activeSubmissions++;
        }

        // Add new submission to the time-decayed averager.
        _averager.update(price, weight, tau);

        submissions[msg.sender] =
            Submission({ price: price, weight: weight, timestamp: block.timestamp });

        submissionCount++;
        lastSubmissionTime = block.timestamp;
        if (submissionCount == 1) {
            firstSubmissionTime = block.timestamp;
        }

        emit PriceSubmitted(msg.sender, price, weight, block.timestamp);
    }

    // --- Queries ---

    function getWeight(address user) external view override returns (uint256 weight) {
        uint256 bullBalance = lockedBull[user];
        uint256 bearBalance = lockedBear[user];

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
        updatedAt = lastSubmissionTime;
        answeredInRound = uint80(count);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
