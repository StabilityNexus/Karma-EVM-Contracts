// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { KarmaAdapterFactory } from "../src/KarmaAdapterFactory.sol";
import { Karma } from "../src/Karma.sol";
import { MockBaseToken, MockCoin, MockPredictionPool } from "./mocks/Mocks.sol";

// Factory tests — deployment, caching, adapter interface.
contract KarmaAdapterFactoryTest is Test {
    KarmaAdapterFactory public factory;

    MockBaseToken public baseToken;
    MockCoin public bullCoin;
    MockCoin public bearCoin;
    MockPredictionPool public pool;

    address public user = makeAddr("user");

    uint256 constant TAU = 124651;
    uint256 constant MIN_BALANCE = 100e18;

    function setUp() public {
        factory = new KarmaAdapterFactory();

        baseToken = new MockBaseToken();
        bullCoin = new MockCoin("Bull", "BULL", address(baseToken));
        bearCoin = new MockCoin("Bear", "BEAR", address(baseToken));
        pool = new MockPredictionPool(address(baseToken), address(bullCoin), address(bearCoin));

        baseToken.mint(address(bullCoin), 10000e18);
        baseToken.mint(address(bearCoin), 10000e18);
        bullCoin.mint(address(this), 10000e18);
        bearCoin.mint(address(this), 10000e18);
    }

    function test_createKarma_deploys() public {
        address adapter = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Test Karma", 0);

        Karma karma = Karma(adapter);
        assertEq(address(karma.pool()), address(pool));
        assertEq(karma.tau(), TAU);
        assertEq(karma.minTotalBalance(), MIN_BALANCE);
    }

    function test_createKarma_caches_adapter() public {
        address a1 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma 1", 0);
        address a2 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma 1 duplicate", 0);
        assertEq(a1, a2, "Same config must return cached adapter");
        assertEq(factory.getKarma(address(pool), TAU, MIN_BALANCE, 0), a1);
    }

    function test_createKarma_different_config_different_adapter() public {
        address a1 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma A", 0);
        address a2 = factory.createKarma(address(pool), TAU, 200e18, "Karma B", 0);
        assertTrue(a1 != a2, "Different minBalance should produce different adapter");
    }

    function test_createAdapter_via_bytes() public {
        bytes memory params =
            abi.encode(address(pool), TAU, MIN_BALANCE, "Generic Adapter", uint256(0));
        vm.prank(user);
        address adapter = factory.createAdapter(params);

        assertTrue(adapter != address(0), "Adapter must deploy successfully");
        Karma karma = Karma(adapter);
        assertEq(address(karma.pool()), address(pool));
    }

    function test_createKarma_defaults() public {
        address adapter = factory.createKarma(address(pool), "Default Karma");
        Karma karma = Karma(adapter);
        assertEq(karma.tau(), 124651, "Should use DEFAULT_TAU");
        assertEq(karma.minTotalBalance(), 100e18, "Should use DEFAULT_MIN_BALANCE");
    }

    function test_createKarma_emits_event() public {
        vm.expectEmit(true, false, false, true);
        emit KarmaAdapterFactory.KarmaCreated(address(pool), address(0), TAU, MIN_BALANCE, "Test");
        factory.createKarma(address(pool), TAU, MIN_BALANCE, "Test", 0);
    }

    function test_createKarma_zero_normalizes_to_default_and_caches() public {
        address a1 = factory.createKarma(address(pool), 0, 0, "Karma 0", 0);
        address a2 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma explicit", 0);
        address a3 = factory.createKarma(address(pool), "Karma default");

        assertEq(a1, a2, "Zero params should normalize and share same adapter as explicit defaults");
        assertEq(a1, a3, "Zero params should normalize and share same adapter as default overload");
        assertEq(factory.getKarma(address(pool), 0, 0, 0), a1);
        assertEq(factory.getKarma(address(pool), TAU, MIN_BALANCE, 0), a1);
    }
}
