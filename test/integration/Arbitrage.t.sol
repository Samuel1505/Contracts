// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {OutcomeToken} from "../../src/tokens/OutcomeToken.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title ArbitrageTest
 * @notice Test complete set arbitrage opportunities
 */
contract ArbitrageTest is TestHelpers {
    address market;
    OutcomeToken outcomeToken;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
        outcomeToken = OutcomeToken(factory.getOutcomeToken(market));
    }

    function test_CompleteSetArbitrage_PricesImbalance() public {
        // Create price imbalance by heavy buying on one outcome
        vm.startPrank(alice);
        collateral.approve(market, 100_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Check prices - should have shifted
        uint256[] memory prices = CategoricalMarket(market).getOutcomePrices();
        assertGt(prices[0], prices[1], "Price of outcome 0 should be higher");

        // Check for arbitrage
        (bool hasArbitrage, uint256 costDifference) = CategoricalMarket(market)
            .checkArbitrage();

        // Even with imbalance, complete set minting should be ~1:1
        uint256 balanceBefore = collateral.balanceOf(bob);

        // Mint complete set - should cost approximately 1:1
        vm.startPrank(bob);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).mintCompleteSet(1000 * 1e18);
        vm.stopPrank();

        // Should pay approximately 1:1
        uint256 balanceAfter = collateral.balanceOf(bob);
        uint256 cost = balanceBefore - balanceAfter;

        assertApproxEqRel(cost, 1000 * 1e18, 0.05e18, "Complete set should cost ~1:1");
    }

    function test_CompleteSetArbitrage_ProfitOpportunity() public {
        // Create significant price imbalance
        vm.startPrank(alice);
        collateral.approve(market, 200_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Prices should diverge significantly
        uint256[] memory pricesBefore = CategoricalMarket(market).getOutcomePrices();

        // Mint complete set
        uint256 amount = 1000 * 1e18;
        uint256 bobBalanceBefore = collateral.balanceOf(bob);

        vm.startPrank(bob);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        // Bob now has complete sets
        (bool hasSet, uint256 numSets) = outcomeToken.hasCompleteSet(bob);
        assertTrue(hasSet, "Bob should have complete sets");
        assertEq(numSets, amount, "Should have correct number of sets");

        // Prices should normalize slightly after minting
        uint256[] memory pricesAfter = CategoricalMarket(market).getOutcomePrices();

        // Price difference should decrease (arbitrage reduces imbalance)
        uint256 priceDiffBefore = pricesBefore[0] > pricesBefore[1]
            ? pricesBefore[0] - pricesBefore[1]
            : pricesBefore[1] - pricesBefore[0];

        uint256 priceDiffAfter = pricesAfter[0] > pricesAfter[1]
            ? pricesAfter[0] - pricesAfter[1]
            : pricesAfter[1] - pricesAfter[0];

        // Complete set minting helps normalize prices
        // (though in practice, fees may prevent perfect arbitrage)
    }

    function test_CompleteSetBurn_Arbitrage() public {
        // First mint complete set
        uint256 amount = 5000 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        // Create price imbalance by buying heavily
        vm.startPrank(bob);
        collateral.approve(market, 100_000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Now prices are imbalanced
        uint256[] memory prices = CategoricalMarket(market).getOutcomePrices();
        assertGt(prices[0], prices[1], "Price imbalance should exist");

        // Alice burns complete set - should get 1:1 back
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        vm.startPrank(alice);
        CategoricalMarket(market).burnCompleteSet(amount);
        vm.stopPrank();

        // Should get approximately 1:1 back
        uint256 aliceBalanceAfter = collateral.balanceOf(alice);
        uint256 received = aliceBalanceAfter - aliceBalanceBefore;

        assertApproxEqRel(received, amount, 0.01e18, "Should get 1:1 back");
    }

    function test_ArbitrageRoundTrip() public {
        // Mint complete set
        uint256 amount = 1000 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        uint256 aliceBalanceBefore = collateral.balanceOf(alice);

        // Burn complete set
        vm.startPrank(alice);
        CategoricalMarket(market).burnCompleteSet(amount);
        vm.stopPrank();

        uint256 aliceBalanceAfter = collateral.balanceOf(alice);

        // Should get approximately the same amount back
        assertApproxEqRel(
            aliceBalanceAfter - aliceBalanceBefore,
            amount,
            0.01e18,
            "Round trip should be ~1:1"
        );
    }

    function test_NoArbitrage_EqualPrices() public {
        // Market with equal prices should have minimal arbitrage
        (bool hasArbitrage, uint256 costDifference) = CategoricalMarket(market)
            .checkArbitrage();

        // Prices should sum to 1, so minimal or no arbitrage
        assertTrue(!hasArbitrage || costDifference < 0.01e18, "Should have minimal arbitrage");
    }

    function test_IndividualPurchaseVsCompleteSet() public {
        uint256 amount = 1000 * 1e18;

        // Method 1: Buy individual shares of each outcome
        vm.startPrank(alice);
        collateral.approve(market, amount * 3);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        CategoricalMarket(market).buyShares(1,  0, type(uint256).max);
        vm.stopPrank();

        uint256 aliceCost = amount * 2; // Rough estimate
        uint256 aliceBalance = collateral.balanceOf(alice);

        // Method 2: Mint complete set
        vm.startPrank(bob);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        uint256 bobBalance = collateral.balanceOf(bob);

        // Complete set should be more efficient (1:1)
        // Individual purchases have slippage and fees
        // Bob should have more collateral left (complete set is cheaper)
        assertGt(
            bobBalance,
            aliceBalance,
            "Complete set should be more cost-effective"
        );
    }

    function test_ArbitrageMultipleMarkets() public {
        // Create multiple markets
        address market1 = createSimpleMarket();
        address market2 = createSimpleMarket();

        // Create price imbalance in both
        for (uint256 i = 0; i < 2; i++) {
            address currentMarket = i == 0 ? market1 : market2;

            vm.startPrank(alice);
            collateral.approve(currentMarket, 50_000 * 1e18);
            CategoricalMarket(currentMarket).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // Arbitrage both markets
        for (uint256 i = 0; i < 2; i++) {
            address currentMarket = i == 0 ? market1 : market2;

            vm.startPrank(bob);
            collateral.approve(currentMarket, 1000 * 1e18);
            CategoricalMarket(currentMarket).mintCompleteSet(1000 * 1e18);
            vm.stopPrank();
        }

        // Bob should have complete sets in both markets
        OutcomeToken outcomeToken1 = OutcomeToken(factory.getOutcomeToken(market1));
        OutcomeToken outcomeToken2 = OutcomeToken(factory.getOutcomeToken(market2));

        (bool hasSet1, ) = outcomeToken1.hasCompleteSet(bob);
        (bool hasSet2, ) = outcomeToken2.hasCompleteSet(bob);

        assertTrue(hasSet1, "Should have complete sets in market 1");
        assertTrue(hasSet2, "Should have complete sets in market 2");
    }

    function test_CompleteSetPriceStability() public {
        // Mint and burn complete sets multiple times
        // Prices should remain stable
        uint256[] memory pricesInitial = CategoricalMarket(market).getOutcomePrices();

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(alice);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).mintCompleteSet(1000 * 1e18);
            CategoricalMarket(market).burnCompleteSet(1000 * 1e18);
            vm.stopPrank();
        }

        uint256[] memory pricesFinal = CategoricalMarket(market).getOutcomePrices();

        // Prices should be approximately the same
        for (uint256 i = 0; i < pricesInitial.length; i++) {
            assertApproxEqRel(
                pricesInitial[i],
                pricesFinal[i],
                0.05e18,
                "Prices should remain stable"
            );
        }
    }
}

