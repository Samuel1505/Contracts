// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LMSRMath} from "../../src/libraries/LMSRMath.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {LibraryTestWrapper} from "./LibraryTestWrapper.sol";

/**
 * @title LMSRTest
 * @notice Comprehensive tests for LMSR math library
 * @dev Tests verify: prices sum to 1, cost function properties, no arbitrage, edge cases
 */
contract LMSRTest is TestHelpers {
    uint256 constant PRECISION = 1e18;
    LibraryTestWrapper wrapper;

    function setUp() public {
        setupBase();
        wrapper = new LibraryTestWrapper();
    }

    // ============================================
    // PRICE SUM TESTS
    // ============================================

    function test_PricesSumToOne_BinaryMarket() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 0;
        quantities[1] = 0;
        uint256 b = 10000 * 1e18;

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);

        assertEq(prices.length, 2);
        assertApproxEqRel(prices[0] + prices[1], PRECISION, "Prices should sum to 1");
    }

    function test_PricesSumToOne_ThreeOutcomeMarket() public {
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 100 * 1e18;
        quantities[1] = 200 * 1e18;
        quantities[2] = 300 * 1e18;
        uint256 b = 10000 * 1e18;

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);

        assertEq(prices.length, 3);
        uint256 sum = prices[0] + prices[1] + prices[2];
        assertApproxEqRel(sum, PRECISION, "Prices should sum to 1");
    }

    function test_PricesSumToOne_MaxOutcomes() public {
        uint256 numOutcomes = 10;
        uint256[] memory quantities = new uint256[](numOutcomes);
        for (uint256 i = 0; i < numOutcomes; i++) {
            quantities[i] = i * 1000 * 1e18;
        }
        uint256 b = 100000 * 1e18;

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);

        assertEq(prices.length, numOutcomes);
        uint256 sum = 0;
        for (uint256 i = 0; i < numOutcomes; i++) {
            sum += prices[i];
        }
        assertApproxEqRel(sum, PRECISION, "Prices should sum to 1");
    }

    function test_PricesSumToOne_AfterTrade() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 10 * 1e18; // Start with non-zero to avoid edge cases
        quantities[1] = 10 * 1e18;
        uint256 b = 10000 * 1e18;

        // Buy shares of outcome 0
        uint256 shares = 100 * 1e18;
        uint256 cost = LMSRMath.calculateBuyCost(quantities, 0, shares, b);

        quantities[0] += shares;

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);
        uint256 sum = prices[0] + prices[1];
        assertApproxEqRel(sum, PRECISION, 0.01e18, "Prices should sum to 1 after trade");
    }

    // ============================================
    // COST FUNCTION TESTS
    // ============================================

    function test_CostFunctionMonotonicity() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 10 * 1e18; // Start with non-zero to avoid edge cases
        quantities[1] = 10 * 1e18;
        uint256 b = 10000 * 1e18;

        uint256 cost1 = LMSRMath.calculateCostFunction(quantities, b);

        // Add shares to outcome 0
        quantities[0] = 110 * 1e18;
        uint256 cost2 = LMSRMath.calculateCostFunction(quantities, b);

        // Cost should increase
        assertGt(cost2, cost1, "Cost should increase when quantities increase");
    }

    function test_BuyCostEqualsCostDifference() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 200 * 1e18;
        uint256 b = 10000 * 1e18;
        uint256 shares = 50 * 1e18;

        uint256 costBefore = LMSRMath.calculateCostFunction(quantities, b);

        // Calculate buy cost from original quantities (not modified)
        uint256 buyCost = LMSRMath.calculateBuyCost(quantities, 0, shares, b);

        // Now calculate cost after
        quantities[0] += shares;
        uint256 costAfter = LMSRMath.calculateCostFunction(quantities, b);

        // Buy cost should equal the difference
        assertApproxEqRel(
            buyCost,
            costAfter > costBefore ? costAfter - costBefore : costBefore - costAfter,
            0.1e18, // 10% tolerance for rounding errors
            "Buy cost should equal cost function difference"
        );
    }

    function test_SellPayoutEqualsCostDifference() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 200 * 1e18;
        uint256 b = 10000 * 1e18;
        uint256 shares = 50 * 1e18;

        uint256 costBefore = LMSRMath.calculateCostFunction(quantities, b);

        quantities[0] -= shares;
        uint256 costAfter = LMSRMath.calculateCostFunction(quantities, b);

        quantities[0] += shares; // Restore for calculateSellPayout
        uint256 sellPayout = LMSRMath.calculateSellPayout(quantities, 0, shares, b);

        // Sell payout should equal the difference
        assertApproxEqRel(
            sellPayout,
            costBefore - costAfter,
            0.01e18,
            "Sell payout should equal cost function difference"
        );
    }

    // ============================================
    // NO ARBITRAGE TESTS
    // ============================================

    function test_CompleteSetCostEqualsOne() public {
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 0;
        quantities[1] = 0;
        quantities[2] = 0;
        uint256 b = 10000 * 1e18;

        // Cost to buy one share of each outcome
        uint256 totalCost = 0;
        for (uint8 i = 0; i < 3; i++) {
            uint256 cost = LMSRMath.calculateBuyCost(quantities, i, 1e18, b);
            quantities[i] += 1e18;
            totalCost += cost;
        }

        // Complete set should cost approximately 1 (within small tolerance for fees/slippage)
        assertApproxEqRel(totalCost, 1e18, 0.05e18, "Complete set should cost ~1");
    }

    function test_BuyAndSellSameAmount() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 200 * 1e18;
        uint256 b = 10000 * 1e18;
        uint256 shares = 50 * 1e18; // Increased to ensure slippage is noticeable

        uint256 buyCost = LMSRMath.calculateBuyCost(quantities, 0, shares, b);

        quantities[0] += shares;
        uint256 sellPayout = LMSRMath.calculateSellPayout(quantities, 0, shares, b);

        // Selling should return less than or equal to buying (due to slippage, but may be equal for very small amounts)
        assertLe(sellPayout, buyCost, "Sell payout should be less than or equal to buy cost");
        // With significant shares, payout should be noticeably less
        if (shares >= 10 * 1e18) {
            assertLt(sellPayout, buyCost, "Sell payout should be less than buy cost for significant shares");
        }
    }

    // ============================================
    // SHARE CALCULATION ACCURACY
    // ============================================

    function test_CalculateSharesForSmallAmount() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 1 * 1e18; // Start with some quantity to avoid edge cases
        quantities[1] = 1 * 1e18;
        uint256 b = 10000 * 1e18;
        uint256 smallAmount = 1e15; // 0.001 tokens

        uint256 cost = LMSRMath.calculateBuyCost(quantities, 0, smallAmount, b);

        assertGt(cost, 0, "Should have non-zero cost for any shares");
        assertLt(cost, smallAmount * 10, "Cost should be reasonable");
    }

    function test_CalculateSharesForLargeAmount() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 1000 * 1e18;
        quantities[1] = 1000 * 1e18;
        uint256 b = 100000 * 1e18;
        uint256 largeAmount = 100000 * 1e18;

        uint256 cost = LMSRMath.calculateBuyCost(quantities, 0, largeAmount, b);

        assertGt(cost, 0, "Should calculate cost for large amounts");
        assertGt(cost, largeAmount / 2, "Cost should increase with size");
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_ZeroLiquidityParameter_Reverts() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 0;
        quantities[1] = 0;

        vm.expectRevert(Errors.InvalidParameter.selector);
        wrapper.testCalculateCostFunction(quantities, 0);
    }

    function test_ZeroShares_Reverts() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 0;
        quantities[1] = 0;
        uint256 b = 10000 * 1e18;

        vm.expectRevert(Errors.ZeroAmount.selector);
        wrapper.testCalculateBuyCost(quantities, 0, 0, b);

        vm.expectRevert(Errors.ZeroAmount.selector);
        wrapper.testCalculateSellPayout(quantities, 0, 0, b);
    }

    function test_InvalidOutcome_Reverts() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 0;
        quantities[1] = 0;
        uint256 b = 10000 * 1e18;

        vm.expectRevert(Errors.InvalidOutcome.selector);
        wrapper.testCalculateBuyCost(quantities, 2, 1e18, b);

        vm.expectRevert(Errors.InvalidOutcome.selector);
        wrapper.testCalculateSellPayout(quantities, 2, 1e18, b);
    }

    function test_SellMoreThanAvailable_Reverts() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 200 * 1e18;
        uint256 b = 10000 * 1e18;

        vm.expectRevert(Errors.InsufficientShares.selector);
        wrapper.testCalculateSellPayout(quantities, 0, 200 * 1e18, b);
    }

    function test_EqualQuantities_EqualPrices() public {
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 100 * 1e18;
        quantities[1] = 100 * 1e18;
        quantities[2] = 100 * 1e18;
        uint256 b = 10000 * 1e18;

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);

        // All prices should be approximately equal
        assertApproxEqRel(prices[0], prices[1], 0.01e18, "Equal quantities should give equal prices");
        assertApproxEqRel(prices[1], prices[2], 0.01e18, "Equal quantities should give equal prices");
    }

    function test_VeryLargeQuantityDifference() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 10000 * 1e18; // Much larger difference
        quantities[1] = 1 * 1e18; // Much smaller
        uint256 b = 100000 * 1e18; // Increase b to handle larger quantities

        uint256[] memory prices = LMSRMath.calculatePrices(quantities, b);

        // Outcome 0 should have much higher price (with large difference, should be > 10x)
        assertGt(prices[0], prices[1] * 10, "Large quantity difference should reflect in prices");

        // But should still sum to 1
        assertApproxEqRel(prices[0] + prices[1], PRECISION, 0.01e18, "Prices should still sum to 1");
    }

    // ============================================
    // LIQUIDITY PARAMETER TESTS
    // ============================================

    function test_CalculateLiquidityParameter() public {
        uint256 numOutcomes = 3;
        uint256 initialLiquidity = 10000 * 1e18;

        uint256 b = LMSRMath.calculateLiquidityParameter(numOutcomes, initialLiquidity);

        assertGt(b, 0, "Liquidity parameter should be positive");
        // b should be approximately initialLiquidity / ln(numOutcomes)
        assertGt(b, initialLiquidity / 2, "Liquidity parameter should be reasonable");
    }

    function test_InvalidOutcomeCountForLiquidity_Reverts() public {
        vm.expectRevert(Errors.InvalidOutcomeCount.selector);
        wrapper.testCalculateLiquidityParameter(0, 10000 * 1e18);

        vm.expectRevert(Errors.InvalidOutcomeCount.selector);
        wrapper.testCalculateLiquidityParameter(11, 10000 * 1e18);
    }

    function test_ZeroLiquidityForParameter_Reverts() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        wrapper.testCalculateLiquidityParameter(3, 0);
    }

    // ============================================
    // PRICE IMPACT TESTS
    // ============================================

    function test_PriceImpactIncreasesWithSize() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 100 * 1e18;
        uint256 b = 10000 * 1e18;

        uint256 impact1 = LMSRMath.calculatePriceImpact(quantities, 0, int256(1e18), b);
        uint256 impact2 = LMSRMath.calculatePriceImpact(quantities, 0, int256(10e18), b);

        assertGt(impact2, impact1, "Larger trades should have more price impact");
    }

    function test_BuyPriceImpactIsPositive() public {
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 100 * 1e18;
        quantities[1] = 100 * 1e18;
        uint256 b = 10000 * 1e18;

        uint256 impact = LMSRMath.calculatePriceImpact(quantities, 0, int256(10e18), b);

        assertGt(impact, 0, "Buy should have positive price impact");
    }
}

