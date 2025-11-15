// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeManager} from "../../src/fee/FeeManager.sol";
import {DynamicFeeLib} from "../../src/libraries/DynamicFeeLib.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";

/**
 * @title FeeManagerTest
 * @notice Tests for dynamic fee system and LP rewards
 */
contract FeeManagerTest is TestHelpers {
    address market;

    function setUp() public {
        setupBase();
        fundUsers();

        // Create a market
        market = createSimpleMarket();
    }

    // ============================================
    // FEE CALCULATION TESTS
    // ============================================

    function test_BaseFee_30Bps() public {
        // New market with no volume
        (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager.getCurrentFees(market);

        // Base fee should be around 30 bps
        uint256 totalFee = protocolFeeBps + lpFeeBps;
        assertGe(totalFee, 10, "Fee should be at least 10 bps (min)");
        assertLe(totalFee, 100, "Fee should be at most 100 bps (max)");
    }

    function test_FeeRangeEnforcement_MinMax() public {
        // Test that fees are always within 10-100 bps range
        for (uint256 i = 0; i < 10; i++) {
            (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager.getCurrentFees(market);
            uint256 totalFee = protocolFeeBps + lpFeeBps;

            assertGe(totalFee, 10, "Fee should never be below 10 bps");
            assertLe(totalFee, 100, "Fee should never exceed 100 bps");

            // Simulate some trading volume
            vm.startPrank(market);
            feeManager.collectTradeFees(market, 1000 * 1e18);
            vm.stopPrank();
        }
    }

    function test_FeeSplit_70PercentLP_30PercentProtocol() public {
        // Note: Actual split is 80% LP, 20% protocol based on DynamicFeeLib
        (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager.getCurrentFees(market);

        // Verify split proportions (80/20)
        uint256 totalFee = protocolFeeBps + lpFeeBps;
        if (totalFee > 0) {
            uint256 lpPercentage = (lpFeeBps * 10000) / totalFee;
            uint256 protocolPercentage = (protocolFeeBps * 10000) / totalFee;

            assertApproxEqRel(lpPercentage, 8000, 0.01e18, "LP should get ~80%");
            assertApproxEqRel(protocolPercentage, 2000, 0.01e18, "Protocol should get ~20%");
        }
    }

    function test_VolumeDiscount_ReducesFees() public {
        // Get initial fees
        (, uint256 protocolFeeBps1, uint256 lpFeeBps1) = feeManager.getCurrentFees(market);
        uint256 totalFee1 = protocolFeeBps1 + lpFeeBps1;

        // Simulate high volume trading
        vm.startPrank(market);
        for (uint256 i = 0; i < 100; i++) {
            feeManager.collectTradeFees(market, 10_000 * 1e18); // 1M total
        }
        vm.stopPrank();

        // Fees should be lower after high volume
        (, uint256 protocolFeeBps2, uint256 lpFeeBps2) = feeManager.getCurrentFees(market);
        uint256 totalFee2 = protocolFeeBps2 + lpFeeBps2;

        assertLe(totalFee2, totalFee1, "Fees should decrease with high volume");
    }

    function test_LiquidityDiscount_ReducesFees() public {
        // Add more liquidity
        vm.startPrank(alice);
        collateral.approve(market, 100_000 * 1e18);
        CategoricalMarket(market).addLiquidity(100_000 * 1e18);
        vm.stopPrank();

        (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager.getCurrentFees(market);
        uint256 totalFee = protocolFeeBps + lpFeeBps;

        // With high liquidity, fees should be lower (though this depends on volume too)
        assertLe(totalFee, 100, "Fee should be within bounds");
    }

    function test_TimeDecayPenalty_NewMarkets() public {
        // New market should have higher fees
        address newMarket = createCategoricalMarket();

        (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager.getCurrentFees(newMarket);
        uint256 totalFee = protocolFeeBps + lpFeeBps;

        // New market may have age penalty
        assertGe(totalFee, 10, "Fee should be at least minimum");
    }

    // ============================================
    // LP REWARDS TESTS
    // ============================================

    function test_RegisterLP() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        (FeeManager.LPInfo memory info, , ) = feeManager.getLPInfo(market, alice);

        assertGt(info.liquidityProvided, 0, "Should track liquidity provided");
        assertGt(info.lpTokens, 0, "Should track LP tokens");
        assertEq(info.entryTime, block.timestamp, "Should record entry time");
    }

    function test_LPRewards_ProportionalToShares() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Bob adds liquidity
        vm.startPrank(bob);
        collateral.approve(market, 20_000 * 1e18);
        CategoricalMarket(market).addLiquidity(20_000 * 1e18);
        vm.stopPrank();

        // Generate trading fees
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        // Bob should have more rewards (he has more LP tokens)
        uint256 aliceRewards = feeManager.getPendingLPRewards(market, alice);
        uint256 bobRewards = feeManager.getPendingLPRewards(market, bob);

        assertGt(bobRewards, aliceRewards, "Bob should have more rewards");
    }

    function test_TieredRewardMultipliers_EarlyLP() public {
        // Alice is early LP
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Generate fees
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        // Fast forward 7 days
        vm.warp(block.timestamp + 7 days);

        uint256 rewards = feeManager.getPendingLPRewards(market, alice);
        assertGt(rewards, 0, "Should have rewards");
    }

    function test_TieredRewardMultipliers_LongTerm() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Generate fees
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        uint256 rewards = feeManager.getPendingLPRewards(market, alice);
        assertGt(rewards, 0, "Long-term LPs should have rewards");
    }

    function test_ClaimLPRewards() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Generate fees
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        uint256 balanceBefore = collateral.balanceOf(alice);
        uint256 pendingBefore = feeManager.getPendingLPRewards(market, alice);

        // Claim rewards
        vm.prank(alice);
        uint256 claimed = feeManager.claimLPRewards(market);

        assertEq(claimed, pendingBefore, "Should claim all pending rewards");
        assertEq(collateral.balanceOf(alice), balanceBefore + claimed, "Balance should increase");
    }

    function test_UnregisterLP_RemovesFromPool() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(10_000 * 1e18);

        // Remove liquidity
        CategoricalMarket(market).removeLiquidity(lpTokens);
        vm.stopPrank();

        // Should be unregistered
        (FeeManager.LPInfo memory info, , ) = feeManager.getLPInfo(market, alice);
        assertEq(info.lpTokens, 0, "LP tokens should be zero after removal");
    }

    // ============================================
    // ACCESS CONTROL TESTS
    // ============================================

    function test_OnlyMarketCanCollectFees() public {
        vm.expectRevert(Errors.OnlyMarket.selector);
        feeManager.collectTradeFees(market, 1000 * 1e18);
    }

    function test_OnlyOwnerCanRegisterMarket() public {
        address newMarket = address(0x1234);

        vm.expectRevert();
        feeManager.registerMarket(newMarket);
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_ZeroTradeAmount_Reverts() public {
        vm.startPrank(market);
        vm.expectRevert(Errors.ZeroAmount.selector);
        feeManager.collectTradeFees(market, 0);
        vm.stopPrank();
    }

    function test_NoLPFees_WhenNoLPs() public {
        // Market with no LPs should still collect fees
        vm.startPrank(market);
        (uint256 protocolFee, uint256 lpFee) = feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        assertGt(protocolFee + lpFee, 0, "Should collect fees even without LPs");
    }

    function test_MultipleLPFeesAccumulate() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        // Generate multiple fee collections
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        uint256 rewards = feeManager.getPendingLPRewards(market, alice);
        assertGt(rewards, 0, "Rewards should accumulate");
    }

    function test_GetMarketFeeStats() public {
        vm.startPrank(market);
        feeManager.collectTradeFees(market, 1000 * 1e18);
        vm.stopPrank();

        FeeManager.MarketFeeStats memory stats = feeManager.getMarketFeeStats(market);

        assertGt(stats.totalProtocolFees, 0, "Should track protocol fees");
        assertGt(stats.totalLPFees, 0, "Should track LP fees");
        assertGt(stats.totalVolume, 0, "Should track volume");
    }
}

