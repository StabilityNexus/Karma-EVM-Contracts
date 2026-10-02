// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { KarmaAdapterFactory } from "../src/KarmaAdapterFactory.sol";
import { Karma } from "../src/Karma.sol";
import { MockBaseToken, MockCoin, MockPredictionPool } from "./mocks/Mocks.sol";

contract MockPoolFactoryWithoutRegister {
    // Post Fate-Solidity PR #44: pool factory does NOT have registerOracle
    // and reverts on any unexpected call
    fallback() external {
        revert("registerOracle removed");
    }
}

contract KarmaAdapterFactoryTest is Test {
    KarmaAdapterFactory public factoryWithPoolFactory;
    KarmaAdapterFactory public factoryWithoutPoolFactory;
    MockPoolFactoryWithoutRegister public mockPoolFactory;

    MockBaseToken public baseToken;
    MockCoin public bullCoin;
    MockCoin public bearCoin;
    MockPredictionPool public pool;

    address public user = makeAddr("user");

    uint256 constant TAU = 124651;
    uint256 constant MIN_BALANCE = 100e18;

    function setUp() public {
        mockPoolFactory = new MockPoolFactoryWithoutRegister();
        factoryWithPoolFactory = new KarmaAdapterFactory(address(mockPoolFactory));
        factoryWithoutPoolFactory = new KarmaAdapterFactory(address(0));

        baseToken = new MockBaseToken();
        bullCoin = new MockCoin("Bull", "BULL", address(baseToken));
        bearCoin = new MockCoin("Bear", "BEAR", address(baseToken));
        pool = new MockPredictionPool(address(baseToken), address(bullCoin), address(bearCoin));

        baseToken.mint(address(bullCoin), 10000e18);
        baseToken.mint(address(bearCoin), 10000e18);
        bullCoin.mint(address(this), 10000e18);
        bearCoin.mint(address(this), 10000e18);
    }

    function test_createKarma_ownership_transferred_to_caller() public {
        vm.prank(user);
        address adapter =
            factoryWithoutPoolFactory.createKarma(address(pool), TAU, MIN_BALANCE, "User Karma");

        Karma karma = Karma(adapter);
        assertEq(karma.owner(), user, "Creator user must be owner");

        // User can call setMinTotalBalance
        vm.prank(user);
        karma.setMinTotalBalance(250e18);
        assertEq(karma.minTotalBalance(), 250e18, "Owner can set minTotalBalance");

        // Non-owner cannot call setMinTotalBalance
        vm.prank(address(this));
        vm.expectRevert();
        karma.setMinTotalBalance(500e18);
    }

    function test_createKarma_caches_adapter() public {
        address a1 =
            factoryWithoutPoolFactory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma 1");
        address a2 = factoryWithoutPoolFactory.createKarma(
            address(pool), TAU, MIN_BALANCE, "Karma 1 duplicate"
        );
        assertEq(a1, a2, "Same config must return cached adapter");
        assertEq(factoryWithoutPoolFactory.getKarma(address(pool), TAU, MIN_BALANCE), a1);
    }

    function test_createAdapter_via_bytes() public {
        bytes memory params = abi.encode(address(pool), TAU, MIN_BALANCE, "Generic Adapter");
        vm.prank(user);
        address adapter = factoryWithoutPoolFactory.createAdapter(params);

        Karma karma = Karma(adapter);
        assertEq(karma.owner(), user, "Caller should be owner when calling createAdapter");
    }

    function test_createKarma_succeeds_with_pool_factory_lacking_registerOracle() public {
        // Verifies Fate-Solidity PR #44 compatibility: does not call registerOracle,
        // so createKarma does not revert against modern Fate pool factories.
        address adapter = factoryWithPoolFactory.createKarma(
            address(pool), TAU, MIN_BALANCE, "Karma with modern factory"
        );

        assertTrue(adapter != address(0), "Adapter must deploy successfully");
    }
}
