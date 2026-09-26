// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IOracle } from "./interfaces/IOracle.sol";
import { IKarmaOracle } from "./interfaces/IKarmaOracle.sol";
import { WeightLib } from "./lib/WeightLib.sol";
import { PriceAverager } from "./lib/PriceAverager.sol";

/// @title IPredictionPoolReader — Minimal read interface for PredictionPool
/// @dev   Only the views Karma needs; keeps Karma decoupled from the full pool.
interface IPredictionPoolReader {
    function baseToken() external view returns (IERC20);
    function bullCoin() external view returns (address);
    function bearCoin() external view returns (address);
}

/// @title ICoinReader — Minimal read interface for Coin price queries
interface ICoinReader {
    function priceSell() external view returns (uint256);
}

/// @title Karma — Permissionless on-chain price-discovery oracle
/// @notice Participants submit price observations weighted by the economic
///         neutrality of their bull/bear positions. A user whose marginal
///         economic exposure to upward and downward price movements is balanced
///         has maximum influence.; a one-sided holder has near-zero influence.
///         Older submissions decay exponentially, so the oracle tracks fresh consensus.
/// @dev    Implements IOracle so PredictionPool can call readValue() unchanged.
///         Internally uses WeightLib for neutrality calculation and PriceAverager for
///         time-decayed weighted averaging, both adapted from neutrality and EWMA patterns.
///

contract Karma is IOracle, IKarmaOracle, Ownable, ReentrancyGuard {
    using PriceAverager for PriceAverager.State;

    //  Constants -----------------------

    /// @notice Fixed-point scale (WAD)
    uint256 public constant SCALE = 1e18;

    /// @notice Coin price denominator (matches Coin.DENOMINATOR)
    uint256 public constant COIN_DENOMINATOR = 100_000;

    /// @notice Default decay time constant (~1-day EWMA half-life)
    uint256 public constant DEFAULT_TAU = 124651;

    /// @notice Default minimum total balance for Sybil resistance (100 tokens in WAD)
    uint256 public constant DEFAULT_MIN_BALANCE = 100e18;

    //  Immutable config ------------------------
    /// @notice The PredictionPool this Karma oracle serves
    IPredictionPoolReader public immutable pool;

    /// @notice The pool's base token
    IERC20 public immutable baseToken;

    /// @notice The pool's bull coin
    address public immutable bullCoin;

    /// @notice The pool's bear coin
    address public immutable bearCoin;

    /// @notice Decay time constant (seconds). Larger = slower decay.
    uint256 public immutable tau;

    //  Mutable state ------------------------------
    /// @notice Human-readable oracle description
    string private _description;

    /// @notice Minimum (bullBalance + bearBalance) required to submit
    uint256 public minTotalBalance;

    /// @notice Time-decayed weighted price averager
    PriceAverager.State private _averager;

    /// @notice Running submission counter (used as Chainlink roundId)
    uint256 public submissionCount;

    /// @notice Timestamp of the very first submission (Chainlink startedAt)
    uint256 public firstSubmissionTime;

    /// @notice Per-user latest submission record
    struct Submission {
        uint256 price;
        uint256 weight;
        uint256 timestamp;
    }

    mapping(address => Submission) public submissions;

    //  Errors    -------------------------------------
    error ZeroPrice();
    error InsufficientBalance(uint256 totalBalance, uint256 minRequired);
    error ZeroWeight();
    error InvalidPool();
    error InvalidTau();

    //  Constructor -------------------------------------

    /// @param _pool            Address of the PredictionPool
    /// @param _tau             Decay time constant in seconds (0 → use DEFAULT_TAU)
    /// @param _minTotalBalance Minimum balance threshold (0 → use DEFAULT_MIN_BALANCE)
    /// @param desc             Human-readable description
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

    //  IOracle implementation (PredictionPool integration)

    /// @inheritdoc IOracle
    function readValue() public view override(IOracle, IKarmaOracle) returns (uint256 value) {
        return _averager.getPrice(tau);
    }

    /// @inheritdoc IOracle
    function readValueInterval()
        external
        view
        override(IOracle, IKarmaOracle)
        returns (uint256 minValue, uint256 maxValue)
    {
        uint256 price = readValue();
        return (price, price);
    }

    /// @inheritdoc IOracle
    function lastUpdated()
        external
        view
        override(IOracle, IKarmaOracle)
        returns (uint256 timestamp)
    {
        return uint256(_averager.lastUpdateTime);
    }

    /// @inheritdoc IOracle
    function description() external view override(IOracle, IKarmaOracle) returns (string memory) {
        return _description;
    }

    //  Karma-specific: price submission full steps ----------------------------
    /// @inheritdoc IKarmaOracle
    function submitPrice(uint256 price) external override nonReentrant {
        if (price == 0) revert ZeroPrice();

        // 1. Read user balances ---------------------------------
        uint256 bullBalance = IERC20(bullCoin).balanceOf(msg.sender);
        uint256 bearBalance = IERC20(bearCoin).balanceOf(msg.sender);

        // 2. Sybil resistance: minimum balance threshold -------------
        uint256 totalBalance = bullBalance + bearBalance;
        if (totalBalance < minTotalBalance) {
            revert InsufficientBalance(totalBalance, minTotalBalance);
        }

        // 3. Compute neutrality weight ---------------------------
        //    Read coin prices and reserves for full normalization
        uint256 bullPrice = ICoinReader(bullCoin).priceSell();
        uint256 bearPrice = ICoinReader(bearCoin).priceSell();
        uint256 bullReserve = baseToken.balanceOf(bullCoin);
        uint256 bearReserve = baseToken.balanceOf(bearCoin);

        uint256 weight = WeightLib.computeWeight(
            bullBalance, bearBalance, bullPrice, bearPrice, bullReserve, bearReserve
        );

        // slither-disable-next-line incorrect-equality
        if (weight < 1) revert ZeroWeight();

        //  4. Update price averager ----------------------------
        _averager.update(price, weight, tau);

        //  5. Store submission record ----------------------------
        submissions[msg.sender] =
            Submission({ price: price, weight: weight, timestamp: block.timestamp });

        submissionCount++;
        if (submissionCount == 1) {
            firstSubmissionTime = block.timestamp;
        }

        //  6. Emit event ----------------------------------
        emit PriceSubmitted(msg.sender, price, weight, block.timestamp);
    }

    //  Karma-specific: read-only queries --------------------------

    /// @inheritdoc IKarmaOracle
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

    /// @inheritdoc IKarmaOracle
    function getSubmission(address user)
        external
        view
        override
        returns (uint256 price, uint256 weight, uint256 timestamp)
    {
        Submission storage sub = submissions[user];
        return (sub.price, sub.weight, sub.timestamp);
    }

    /// @notice Check whether the oracle has a valid price
    function hasPrice() external view returns (bool) {
        return _averager.hasPrice();
    }

    //  Chainlink-compatible-----------------------------

    /// @inheritdoc IKarmaOracle
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

    /// @notice Chainlink-compatible decimals
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Chainlink-compatible version
    function version() external pure returns (uint256) {
        return 1;
    }

    //  Admin     -------------------------------

    /// @notice Update the minimum balance threshold for Sybil resistance
    /// @param newMinBalance New minimum (bullBalance + bearBalance) required
    function setMinTotalBalance(uint256 newMinBalance) external onlyOwner {
        uint256 oldMin = minTotalBalance;
        minTotalBalance = newMinBalance;
        emit MinBalanceUpdated(oldMin, newMinBalance);
    }
}
