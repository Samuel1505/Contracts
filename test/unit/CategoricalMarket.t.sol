// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {OutcomeToken} from "../../src/tokens/OutcomeToken.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title CategoricalMarketTest
 * @notice Comprehensive tests for market core functionality
 */
contract CategoricalMarketTest is TestHelpers {
    address market;
    OutcomeToken outcomeToken;
    LPToken lpToken;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
        outcomeToken = OutcomeToken(factory.getOutcomeToken(market));
        lpToken = LPToken(factory.getLPToken(market));
    }

    // ============================================
    // INITIALIZATION TESTS
    // ============================================

    function test_MarketInitialization() public {
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();

        assertEq(uint256(info.status), uint256(CategoricalMarket.MarketStatus.ACTIVE), "Market should be active");
        assertGt(info.resolutionTime, block.timestamp, "Resolution time should be in future");
        assertGt(info.liquidityParameter, 0, "Liquidity parameter should be set");
    }

    function test_InitializeTwice_Reverts() public {
        // Get token addresses from factory
        address outcomeTokenAddr = factory.getOutcomeToken(market);
        address lpTokenAddr = factory.getLPToken(market);
        
        // Try to initialize again
        vm.expectRevert(Errors.AlreadyInitialized.selector);
        CategoricalMarket(market).initialize(
            stringToBytes32("test"),
            2,
            block.timestamp + 7 days,
            oracle,
            10_000 * 1e18,
            outcomeTokenAddr,
            lpTokenAddr
        );
    }

    // ============================================
    // COMPLETE SET TESTS
    // ============================================

    function test_MintCompleteSet() public {
        uint256 amount = 100 * 1e18;

        uint256 balanceBefore = collateral.balanceOf(alice);

        vm.startPrank(alice);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        // Check balances
        assertEq(outcomeToken.balanceOf(alice, 0), amount, "Should have outcome 0 shares");
        assertEq(outcomeToken.balanceOf(alice, 1), amount, "Should have outcome 1 shares");
        assertEq(collateral.balanceOf(alice), balanceBefore - amount, "Should pay 1:1");

        // Check market collateral increased
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        assertGe(info.totalCollateral, amount, "Market collateral should increase");
    }

    function test_BurnCompleteSet() public {
        uint256 amount = 100 * 1e18;

        // First mint
        vm.startPrank(alice);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        uint256 balanceBefore = collateral.balanceOf(alice);

        // Then burn
        vm.startPrank(alice);
        CategoricalMarket(market).burnCompleteSet(amount);
        vm.stopPrank();

        // Check balances
        assertEq(outcomeToken.balanceOf(alice, 0), 0, "Should have no outcome 0 shares");
        assertEq(outcomeToken.balanceOf(alice, 1), 0, "Should have no outcome 1 shares");
        assertEq(collateral.balanceOf(alice), balanceBefore + amount, "Should get 1:1 back");
    }

    function test_MintCompleteSet_Zero_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        CategoricalMarket(market).mintCompleteSet(0);
        vm.stopPrank();
    }

    function test_BurnCompleteSet_Insufficient_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.InsufficientShares.selector);
        CategoricalMarket(market).burnCompleteSet(100 * 1e18);
        vm.stopPrank();
    }

    // ============================================
    // TRADING TESTS
    // ============================================

    function test_BuyShares() public {
        uint256 maxCost = 1000 * 1e18;
        uint8 outcome = 0;

        uint256 balanceBefore = collateral.balanceOf(alice);
        uint256 sharesBefore = outcomeToken.balanceOf(alice, outcome);

        vm.startPrank(alice);
        collateral.approve(market, maxCost);
        (uint256 shares, uint256 cost) = CategoricalMarket(market).buyShares(
            outcome,
            0, // minShares
            maxCost
        );
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertLe(cost, maxCost, "Cost should not exceed max");
        assertEq(outcomeToken.balanceOf(alice, outcome), sharesBefore + shares, "Shares should increase");
        assertEq(collateral.balanceOf(alice), balanceBefore - cost, "Collateral should decrease");
    }

    function test_BuyShares_SlippageProtection() public {
        uint256 maxCost = 1000 * 1e18;
        uint256 minShares = 10000 * 1e18; // Unrealistic min

        vm.startPrank(alice);
        collateral.approve(market, maxCost);
        vm.expectRevert(Errors.SlippageExceeded.selector);
        CategoricalMarket(market).buyShares(0, minShares, maxCost);
        vm.stopPrank();
    }

    function test_SellShares() public {
        // First buy shares
        uint256 maxCost = 1000 * 1e18;
        uint8 outcome = 0;

        vm.startPrank(alice);
        collateral.approve(market, maxCost);
        (uint256 shares, ) = CategoricalMarket(market).buyShares(outcome, 0, maxCost);
        vm.stopPrank();

        uint256 balanceBefore = collateral.balanceOf(alice);
        uint256 sharesBefore = outcomeToken.balanceOf(alice, outcome);

        // Sell shares
        vm.startPrank(alice);
        uint256 payout = CategoricalMarket(market).sellShares(outcome, shares, 0);
        vm.stopPrank();

        assertGt(payout, 0, "Should receive payout");
        assertEq(outcomeToken.balanceOf(alice, outcome), sharesBefore - shares, "Shares should decrease");
        assertGt(collateral.balanceOf(alice), balanceBefore, "Collateral should increase");
    }

    function test_SellShares_SlippageProtection() public {
        // Buy shares first
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        (uint256 shares, ) = CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        uint256 minPayout = 10000 * 1e18; // Unrealistic min

        vm.startPrank(alice);
        vm.expectRevert(Errors.SlippageExceeded.selector);
        CategoricalMarket(market).sellShares(0, shares, minPayout);
        vm.stopPrank();
    }

    function test_BuyShares_InvalidOutcome_Reverts() public {
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        vm.expectRevert(Errors.InvalidOutcome.selector);
        CategoricalMarket(market).buyShares(2, 0, 1000 * 1e18); // Only 2 outcomes (0, 1)
        vm.stopPrank();
    }

    function test_SellShares_Insufficient_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.InsufficientShares.selector);
        CategoricalMarket(market).sellShares(0, 100 * 1e18, 0);
        vm.stopPrank();
    }

    function test_MarketPricesSumToOne() public {
        uint256[] memory prices = CategoricalMarket(market).getOutcomePrices();

        uint256 sum = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            sum += prices[i];
        }

        assertApproxEqRel(sum, 1e18, 0.01e18, "Prices should sum to 1");
    }

    // ============================================
    // LIQUIDITY TESTS
    // ============================================

    function test_AddLiquidity() public {
        uint256 amount = 10_000 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(amount);
        vm.stopPrank();

        assertGt(lpTokens, 0, "Should receive LP tokens");
        assertEq(lpToken.balanceOf(alice), lpTokens, "Should have LP tokens");

        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        assertGe(info.liquidityPool, amount, "Liquidity pool should increase");
    }

    function test_AddLiquidity_FirstLP() public {
        // This is the second LP (admin already added initial liquidity)
        uint256 amount = 10_000 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(amount);
        vm.stopPrank();

        assertGt(lpTokens, 0, "Should receive LP tokens");
    }

    function test_RemoveLiquidity() public {
        uint256 amount = 10_000 * 1e18;

        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, amount);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(amount);
        vm.stopPrank();

        uint256 balanceBefore = collateral.balanceOf(alice);

        // Remove liquidity
        vm.startPrank(alice);
        uint256 collateralReturned = CategoricalMarket(market).removeLiquidity(lpTokens);
        vm.stopPrank();

        assertGt(collateralReturned, 0, "Should return collateral");
        assertEq(lpToken.balanceOf(alice), 0, "Should have no LP tokens");
        assertGt(collateral.balanceOf(alice), balanceBefore, "Collateral should increase");
    }

    function test_RemoveLiquidity_Insufficient_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.NoLPTokens.selector);
        CategoricalMarket(market).removeLiquidity(100 * 1e18);
        vm.stopPrank();
    }

    function test_AddLiquidity_Zero_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        CategoricalMarket(market).addLiquidity(0);
        vm.stopPrank();
    }

    // ============================================
    // RESOLUTION & CLAIMS TESTS
    // ============================================

    function test_ResolveMarket() public {
        // Warp to resolution time
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        (info, , ) = CategoricalMarket(market).getMarketState();
        assertEq(
            uint256(info.status),
            uint256(CategoricalMarket.MarketStatus.RESOLVED),
            "Market should be resolved"
        );
        assertEq(info.winningOutcome, 0, "Winning outcome should be set");
    }

    function test_ResolveMarket_NotOracle_Reverts() public {
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.expectRevert(Errors.OnlyOracle.selector);
        CategoricalMarket(market).resolveMarket(0);
    }

    function test_ResolveMarket_BeforeTime_Reverts() public {
        vm.expectRevert(Errors.ResolutionTimeNotReached.selector);
        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);
    }

    function test_ClaimWinnings() public {
        // Buy winning outcome shares
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        uint256 shares = outcomeToken.balanceOf(alice, 0);
        uint256 balanceBefore = collateral.balanceOf(alice);

        // Resolve market
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        // Claim winnings
        vm.prank(alice);
        uint256 winnings = CategoricalMarket(market).claimWinnings();

        assertEq(winnings, shares, "Winnings should equal shares");
        assertEq(collateral.balanceOf(alice), balanceBefore + shares, "Balance should increase");
        assertEq(outcomeToken.balanceOf(alice, 0), 0, "Shares should be burned");
        assertTrue(CategoricalMarket(market).hasClaimed(alice), "Should be marked as claimed");
    }

    function test_ClaimWinnings_Twice_Reverts() public {
        // Buy shares and resolve
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        // Claim once
        vm.prank(alice);
        CategoricalMarket(market).claimWinnings();

        // Try to claim again
        vm.expectRevert(Errors.AlreadyClaimed.selector);
        vm.prank(alice);
        CategoricalMarket(market).claimWinnings();
    }

    function test_ClaimWinnings_NoShares_Reverts() public {
        // Resolve market
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        // Try to claim without shares
        vm.expectRevert(Errors.NothingToClaim.selector);
        vm.prank(alice);
        CategoricalMarket(market).claimWinnings();
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_GetUserPosition() public {
        // Buy shares
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        (
            uint256[] memory balances,
            uint256 currentValue,
            uint256 potentialWinnings
        ) = CategoricalMarket(market).getUserPosition(alice);

        assertEq(balances.length, 2, "Should have balances for all outcomes");
        assertGt(balances[0], 0, "Should have shares in outcome 0");
        assertGt(currentValue, 0, "Should have current value");
        assertEq(potentialWinnings, balances[0], "Potential winnings should equal max balance");
    }

    function test_SimulateBuy() public {
        (
            uint256 shares,
            uint256 totalCost,
            uint256 priceImpact
        ) = CategoricalMarket(market).simulateBuy(0, 1000 * 1e18);

        assertGt(shares, 0, "Should estimate shares");
        assertGt(totalCost, 0, "Should estimate total cost");
        assertGe(priceImpact, 0, "Should calculate price impact");
    }

    function test_SimulateSell() public {
        // Buy shares first
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        uint256 shares = outcomeToken.balanceOf(alice, 0);

        (uint256 payout, uint256 priceImpact) = CategoricalMarket(market).simulateSell(0, shares);

        assertGt(payout, 0, "Should estimate payout");
        assertGe(priceImpact, 0, "Should calculate price impact");
    }

    function test_CheckArbitrage() public {
        (bool hasArbitrage, uint256 costDifference) = CategoricalMarket(market).checkArbitrage();

        // New market should have minimal arbitrage
        assertTrue(!hasArbitrage || costDifference < 0.01e18, "Should have minimal arbitrage");
    }

    // ============================================
    // ACCESS CONTROL TESTS
    // ============================================

    function test_OnlyActive_Resolved_Reverts() public {
        // Resolve market
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        // Try to trade after resolution
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        vm.expectRevert(Errors.MarketNotActive.selector);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_MaxOutcomes() public {
        address market10 = createCustomMarket("test", 10, 7 days, 10_000 * 1e18);

        uint256[] memory prices = CategoricalMarket(market10).getOutcomePrices();
        assertEq(prices.length, 10, "Should have 10 outcomes");
    }

    function test_MinOutcomes() public {
        // Binary market already tested in setUp
        uint256[] memory prices = CategoricalMarket(market).getOutcomePrices();
        assertEq(prices.length, 2, "Should have 2 outcomes");
    }
}

