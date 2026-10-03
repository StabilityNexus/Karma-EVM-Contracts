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
        address adapter = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Test Karma");

        Karma karma = Karma(adapter);
        assertEq(address(karma.pool()), address(pool));
        assertEq(karma.tau(), TAU);
        assertEq(karma.minTotalBalance(), MIN_BALANCE);
    }

    function test_createKarma_caches_adapter() public {
        address a1 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma 1");
        address a2 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma 1 duplicate");
        assertEq(a1, a2, "Same config must return cached adapter");
        assertEq(factory.getKarma(address(pool), TAU, MIN_BALANCE), a1);
    }

    function test_createKarma_different_config_different_adapter() public {
        address a1 = factory.createKarma(address(pool), TAU, MIN_BALANCE, "Karma A");
        address a2 = factory.createKarma(address(pool), TAU, 200e18, "Karma B");
        assertTrue(a1 != a2, "Different minBalance should produce different adapter");
    }

    function test_createAdapter_via_bytes() public {
        bytes memory params = abi.encode(address(pool), TAU, MIN_BALANCE, "Generic Adapter");
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
        factory.createKarma(address(pool), TAU, MIN_BALANCE, "Test");
    }
}
