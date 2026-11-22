// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { AccumulatorVault } from "../src/AccumulatorVault.sol";
import { Coin } from "../src/Coin.sol";
import { Karma } from "../src/Karma.sol";
import { KarmaAdapterFactory } from "../src/KarmaAdapterFactory.sol";
import { PredictionPool } from "../src/PredictionPool.sol";
import { PredictionPoolFactory } from "../src/PredictionPoolFactory.sol";
import { MockBaseToken } from "./mocks/Mocks.sol";
import { MockOracle } from "./PoolSystem.t.sol";

// The same coins must not give weight to more than one submission at a time.
contract KarmaLockedWeightTest is Test {
    MockBaseToken private token;
    PredictionPool private pool;
    Coin private bull;
    Coin private bear;
    Karma private karma;
    address private alice = makeAddr("alice");
    address private attacker = makeAddr("attacker");

    function setUp() public {
        token = new MockBaseToken();
        PredictionPoolFactory factory = new PredictionPoolFactory(
            address(new AccumulatorVault(makeAddr("dev"), makeAddr("receiver")))
        );
        token.mint(address(this), 1_000e18);
        token.approve(address(factory), type(uint256).max);
        pool = PredictionPool(
            factory.createPool(
                "Pool",
                address(token),
                address(new MockOracle(1e18)),
                "Bull",
                "BULL",
                "Bear",
                "BEAR",
                500,
                500,
                500,
                300,
                1_000e18
            )
        );
        bull = pool.bullCoin();
        bear = pool.bearCoin();
        karma = Karma(new KarmaAdapterFactory().createKarma(address(pool), "Karma"));

        // The creator locks its 500 bull and 500 bear and reports the honest price.
        _lockAll(address(this));
        karma.submitPrice(1e18);
        pool.updateOracle(address(karma));

        _buy(alice, bear, 1_000e18);
        _buy(attacker, bull, 1_000e18);
        _buy(attacker, bear, 60e18);
        vm.warp(block.timestamp + 1 hours);
    }

    function test_movingLockedCoinsToNewAddressesAddsNoWeight() public {
        uint256 snap = vm.snapshotState();
        _submitThroughAddresses(1, 1.5e18);
        uint256 oneAddress = karma.readValue();
        vm.revertToState(snap);
        _submitThroughAddresses(40, 1.5e18);
        uint256 manyAddresses = karma.readValue();

        assertGt(oneAddress, 1e18);
        assertEq(manyAddresses, oneAddress, "40 addresses moved the price more than 1");
    }

    function test_attackerGainsNothingFromExtraAddresses() public {
        uint256 snap = vm.snapshotState();
        uint256 oneAddressOut = _sellAfterRebalance(_submitThroughAddresses(1, 1.5e18));
        vm.revertToState(snap);
        uint256 manyAddressesOut = _sellAfterRebalance(_submitThroughAddresses(40, 1.5e18));

        assertEq(manyAddressesOut, oneAddressOut);
    }

    function test_doublingPriceThroughNewAddressesDoesNotCompound() public {
        address holder = attacker;
        for (uint256 i; i < 120; i++) {
            _lockAll(holder);
            uint256 doubled = 2 * karma.readValue();
            vm.prank(holder);
            karma.submitPrice(doubled);
            holder = _unlockAndMove(holder, _hop("doubling", i));
        }

        assertLt(karma.readValue(), 2e18, "bounded prices compounded through moved coins");
    }

    function test_unlockRemovesTheSubmission() public {
        _lockAll(attacker);
        vm.prank(attacker);
        karma.submitPrice(1.5e18);
        assertGt(karma.readValue(), 1e18);

        (uint256 lockedBull, uint256 lockedBear) = karma.lockedBalances(attacker);
        vm.prank(attacker);
        karma.unlock(lockedBull, lockedBear);

        assertEq(karma.readValue(), 1e18, "the unlocked coins still count");
        (,, uint256 timestamp) = karma.getSubmission(attacker);
        assertEq(timestamp, 0);
        assertEq(bull.balanceOf(attacker), lockedBull);
        assertEq(bear.balanceOf(attacker), lockedBear);
    }

    function test_coinsOnlyInTheWalletGiveNoWeight() public {
        assertEq(karma.getWeight(attacker), 0);

        vm.expectRevert(abi.encodeWithSelector(Karma.InsufficientBalance.selector, 0, 100e18));
        vm.prank(attacker);
        karma.submitPrice(1.5e18);
    }

    function test_unlockMoreThanLockedReverts() public {
        _lockAll(attacker);
        (uint256 lockedBull, uint256 lockedBear) = karma.lockedBalances(attacker);

        vm.expectRevert(Karma.InsufficientLocked.selector);
        vm.prank(attacker);
        karma.unlock(lockedBull + 1, lockedBear);

        vm.expectRevert(Karma.InsufficientLocked.selector);
        vm.prank(attacker);
        karma.unlock(lockedBull, lockedBear + 1);
    }

    function test_unlockLowersLockedBalances() public {
        _lockAll(attacker);
        (uint256 lockedBull, uint256 lockedBear) = karma.lockedBalances(attacker);

        vm.prank(attacker);
        karma.unlock(lockedBull / 2, lockedBear / 2);
        (uint256 bullLeft, uint256 bearLeft) = karma.lockedBalances(attacker);
        assertEq(bullLeft, lockedBull - lockedBull / 2);
        assertEq(bearLeft, lockedBear - lockedBear / 2);

        // The same coins cannot be unlocked twice.
        vm.expectRevert(Karma.InsufficientLocked.selector);
        vm.prank(attacker);
        karma.unlock(lockedBull, lockedBear);
    }

    // Rounding must not leave a price behind once every reporter has unlocked.
    function testFuzz_noPriceLeftAfterEveryoneUnlocks(uint256 seed) public {
        address[5] memory reporters;
        // Keep time in a local: block.timestamp can be cached in tests built with via_ir.
        uint256 time = block.timestamp;
        for (uint256 i; i < reporters.length; i++) {
            reporters[i] = _hop("reporter", i);
            uint256 amount = 100e18 + uint256(keccak256(abi.encode(seed, i))) % 2_000e18;
            _buy(reporters[i], bull, amount);
            _buy(reporters[i], bear, amount);
            _lockAll(reporters[i]);
            vm.prank(reporters[i]);
            karma.submitPrice(0.5e18 + uint256(keccak256(abi.encode(seed, i, "price"))) % 3e18);
            time += 1 + uint256(keccak256(abi.encode(seed, i, "t"))) % 2 days;
            vm.warp(time);
        }

        _unlockAll(address(this));
        for (uint256 i; i < reporters.length; i++) {
            time += uint256(keccak256(abi.encode(seed, i, "u"))) % 1 days;
            vm.warp(time);
            _unlockAll(reporters[i]);
        }

        assertEq(karma.readValue(), 0, "a price was left with no reporters");
        assertFalse(karma.hasPrice());
        assertEq(karma.activeSubmissions(), 0);
    }

    function test_unlockDoesNotLookLikeANewPrice() public {
        uint256 submittedAt = karma.lastUpdated();
        vm.warp(submittedAt + 1 days);

        _unlockAll(address(this));

        assertEq(karma.lastUpdated(), submittedAt);
        (,,, uint256 updatedAt,) = karma.latestRoundData();
        assertEq(updatedAt, submittedAt);
    }

    // Each address locks the same coins and submits. Moving them on unlocks them first.
    // The last address keeps its coins locked and is returned.
    function _submitThroughAddresses(uint256 count, uint256 price)
        private
        returns (address holder)
    {
        holder = attacker;
        for (uint256 i; i < count; i++) {
            if (i > 0) holder = _unlockAndMove(holder, _hop("same coins", i));
            _lockAll(holder);
            vm.prank(holder);
            karma.submitPrice(price);
        }
    }

    // The pool rebalances on the reported price.
    // Then the coins go back to the attacker and are sold.
    function _sellAfterRebalance(address holder) private returns (uint256 out) {
        pool.rebalance();
        if (holder == attacker) _unlockAll(attacker);
        else _unlockAndMove(holder, attacker);
        vm.startPrank(attacker);
        out = bull.sell(bull.balanceOf(attacker));
        out += bear.sell(bear.balanceOf(attacker));
        vm.stopPrank();
    }

    function _unlockAndMove(address from, address to) private returns (address) {
        _unlockAll(from);
        vm.startPrank(from);
        assertTrue(bull.transfer(to, bull.balanceOf(from)));
        assertTrue(bear.transfer(to, bear.balanceOf(from)));
        vm.stopPrank();
        return to;
    }

    function _lockAll(address who) private {
        uint256 bullAmount = bull.balanceOf(who);
        uint256 bearAmount = bear.balanceOf(who);
        vm.startPrank(who);
        bull.approve(address(karma), bullAmount);
        bear.approve(address(karma), bearAmount);
        karma.lock(bullAmount, bearAmount);
        vm.stopPrank();
    }

    function _unlockAll(address who) private {
        (uint256 bullAmount, uint256 bearAmount) = karma.lockedBalances(who);
        vm.prank(who);
        karma.unlock(bullAmount, bearAmount);
    }

    function _hop(string memory label, uint256 i) private returns (address) {
        return makeAddr(string.concat(label, " ", vm.toString(i)));
    }

    function _buy(address who, Coin coin, uint256 amount) private returns (uint256 got) {
        token.mint(who, amount);
        vm.startPrank(who);
        token.approve(address(coin), amount);
        got = coin.buy(who, amount);
        vm.stopPrank();
    }
}
