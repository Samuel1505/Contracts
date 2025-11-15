// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {OutcomeToken} from "../../src/tokens/OutcomeToken.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title FullMarketFlowTest
 * @notice End-to-end integration test for complete market lifecycle
 */
contract FullMarketFlowTest is TestHelpers {
    address market;
    OutcomeToken outcomeToken;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
        outcomeToken = OutcomeToken(factory.getOutcomeToken(market));
    }

    function test_FullMarketLifecycle() public {
        // 1. Market Creation
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        assertEq(
            uint256(info.status),
            uint256(CategoricalMarket.MarketStatus.ACTIVE),
            "Market should be active"
        );

        // 2. Initial Liquidity Provision
        uint256 initialLP = info.liquidityPool;
        assertGt(initialLP, 0, "Should have initial liquidity");

        // 3. Add More Liquidity
        vm.startPrank(alice);
        collateral.approve(market, 20_000 * 1e18);
        CategoricalMarket(market).addLiquidity(20_000 * 1e18);
        vm.stopPrank();

        (info, , ) = CategoricalMarket(market).getMarketState();
        assertGt(info.liquidityPool, initialLP, "Liquidity should increase");

        // 4. Multiple Users Trading
        // Alice buys outcome 0
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max); // Use max uint256 for maxCost
        vm.stopPrank();

        // Bob buys outcome 1
        vm.startPrank(bob);
        collateral.approve(market, 3000 * 1e18);
        CategoricalMarket(market).buyShares(1,  0, type(uint256).max); // Use max uint256 for maxCost
        vm.stopPrank();

        // Carol mints complete set
        vm.startPrank(carol);
        collateral.approve(market, 2000 * 1e18);
        CategoricalMarket(market).mintCompleteSet(2000 * 1e18);
        vm.stopPrank();

        // 5. Check Positions
        (
            uint256[] memory aliceBalances,
            ,
            uint256 aliceWinnings
        ) = CategoricalMarket(market).getUserPosition(alice);
        assertGt(aliceBalances[0], 0, "Alice should have outcome 0 shares");
        assertGt(aliceWinnings, 0, "Alice should have potential winnings");

        // 6. Bob sells some shares
        uint256 bobShares = outcomeToken.balanceOf(bob, 1);
        vm.startPrank(bob);
        CategoricalMarket(market).sellShares(1, bobShares / 2, 0);
        vm.stopPrank();

        // 7. Market Resolution
        vm.warp(info.resolutionTime);
        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        (info, , ) = CategoricalMarket(market).getMarketState();
        assertEq(
            uint256(info.status),
            uint256(CategoricalMarket.MarketStatus.RESOLVED),
            "Market should be resolved"
        );
        assertEq(info.winningOutcome, 0, "Winning outcome should be 0");

        // 8. Claim Winnings
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        uint256 aliceShares = outcomeToken.balanceOf(alice, 0);

        vm.prank(alice);
        uint256 winnings = CategoricalMarket(market).claimWinnings();

        assertEq(winnings, aliceShares, "Winnings should equal shares");
        assertEq(
            collateral.balanceOf(alice),
            aliceBalanceBefore + winnings,
            "Balance should increase"
        );
        assertEq(
            outcomeToken.balanceOf(alice, 0),
            0,
            "Shares should be burned after claim"
        );

        // 9. Carol burns complete set (she has both outcomes)
        uint256 carolBalanceBefore = collateral.balanceOf(carol);
        vm.startPrank(carol);
        CategoricalMarket(market).burnCompleteSet(1000 * 1e18);
        vm.stopPrank();

        assertGt(
            collateral.balanceOf(carol),
            carolBalanceBefore,
            "Carol should get collateral back"
        );
    }

    function test_MultipleMarketsFlow() public {
        // Create multiple markets
        address market1 = createSimpleMarket();
        address market2 = createCategoricalMarket();
        address market3 = createSimpleMarket();

        // Trade in all markets
        for (uint256 i = 0; i < 3; i++) {
            address currentMarket = i == 0 ? market1 : (i == 1 ? market2 : market3);

            vm.startPrank(alice);
            collateral.approve(currentMarket, 1000 * 1e18);
            CategoricalMarket(currentMarket).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // All markets should have alice's positions
        (uint256[] memory balances1, , ) = CategoricalMarket(market1).getUserPosition(
            alice
        );
        (uint256[] memory balances2, , ) = CategoricalMarket(market2).getUserPosition(
            alice
        );
        (uint256[] memory balances3, , ) = CategoricalMarket(market3).getUserPosition(
            alice
        );

        assertGt(balances1[0], 0, "Should have shares in market 1");
        assertGt(balances2[0], 0, "Should have shares in market 2");
        assertGt(balances3[0], 0, "Should have shares in market 3");
    }

    function test_HighVolumeTrading() public {
        // Simulate high volume trading
        for (uint256 i = 0; i < 50; i++) {
            address user = i % 2 == 0 ? alice : bob;
            uint8 outcome = uint8(i % 2);

            vm.startPrank(user);
            collateral.approve(market, 100 * 1e18);
            CategoricalMarket(market).buyShares(outcome,  0, type(uint256).max); // Use max uint256 for maxCost
            vm.stopPrank();
        }

        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();

        assertGt(info.totalVolume, 0, "Should track total volume");
    }

    function test_LiquidityProvidersEarnFees() public {
        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Generate trading fees
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max); // Use max uint256 for maxCost
            vm.stopPrank();
        }

        // Check pending LP rewards
        uint256 pendingRewards = feeManager.getPendingLPRewards(market, alice);
        assertGt(pendingRewards, 0, "LP should have pending rewards");
    }

    function test_PriceDiscovery() public {
        // Initial prices should be approximately equal
        uint256[] memory pricesInitial = CategoricalMarket(market).getOutcomePrices();
        assertApproxEqRel(
            pricesInitial[0],
            pricesInitial[1],
            0.05e18,
            "Initial prices should be similar"
        );

        // Heavy buying of outcome 0
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max); // Use max uint256 for maxCost
        vm.stopPrank();

        // Prices should shift
        uint256[] memory pricesAfter = CategoricalMarket(market).getOutcomePrices();
        assertGt(
            pricesAfter[0],
            pricesInitial[0],
            "Price of outcome 0 should increase"
        );
        assertLt(
            pricesAfter[1],
            pricesInitial[1],
            "Price of outcome 1 should decrease"
        );

        // Prices should still sum to 1
        uint256 sum = pricesAfter[0] + pricesAfter[1];
        assertApproxEqRel(sum, 1e18, 0.01e18, "Prices should still sum to 1");
    }

    function test_CompleteSetArbitrage() public {
        // Buy heavily on one outcome to create price imbalance
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max); // Use max uint256 for maxCost
        vm.stopPrank();

        // Check for arbitrage
        (bool hasArbitrage, uint256 costDifference) = CategoricalMarket(market)
            .checkArbitrage();

        // Prices may have imbalance but complete set should still be ~1:1
        if (hasArbitrage) {
            // If arbitrage exists, minting complete set should be profitable
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).mintCompleteSet(1000 * 1e18);
            vm.stopPrank();

            // Bob should have complete sets
            (bool hasSet, ) = outcomeToken.hasCompleteSet(bob);
            assertTrue(hasSet, "Bob should have complete sets");
        }
    }

    function test_MarketStateConsistency() public {
        // Perform various operations
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(5_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        CategoricalMarket(market).mintCompleteSet(1_000 * 1e18);
        vm.stopPrank();

        // Market state should be consistent
        (
            CategoricalMarket.MarketInfo memory info,
            uint256[] memory prices,
            uint256[] memory quantities
        ) = CategoricalMarket(market).getMarketState();

        // Prices should sum to 1
        uint256 priceSum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            priceSum += prices[i];
        }
        assertApproxEqRel(priceSum, 1e18, 0.01e18, "Prices should sum to 1");

        // Liquidity pool should be positive
        assertGt(info.liquidityPool, 0, "Liquidity pool should be positive");

        // Quantities should match outcomes
        assertEq(quantities.length, 2, "Should have quantities for both outcomes");
    }
}

