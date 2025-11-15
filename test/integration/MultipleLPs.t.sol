// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {FeeManager} from "../../src/fee/FeeManager.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title MultipleLPsTest
 * @notice Test LP competition scenarios and reward distribution
 */
contract MultipleLPsTest is TestHelpers {
    address market;
    LPToken lpToken;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
        lpToken = LPToken(factory.getLPToken(market));
    }

    function test_MultipleLPs_ProportionalRewards() public {
        // Alice adds 30K liquidity
        vm.startPrank(alice);
        collateral.approve(market, 30_000 * 1e18);
        uint256 aliceLPTokens = CategoricalMarket(market).addLiquidity(30_000 * 1e18);
        vm.stopPrank();

        // Bob adds 70K liquidity
        vm.startPrank(bob);
        collateral.approve(market, 70_000 * 1e18);
        uint256 bobLPTokens = CategoricalMarket(market).addLiquidity(70_000 * 1e18);
        vm.stopPrank();

        // Generate trading fees
        for (uint256 i = 0; i < 20; i++) {
            vm.startPrank(carol);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(uint8(i % 2),  0, type(uint256).max);
            vm.stopPrank();
        }

        // Check rewards
        uint256 aliceRewards = feeManager.getPendingLPRewards(market, alice);
        uint256 bobRewards = feeManager.getPendingLPRewards(market, bob);

        // Bob should have more rewards (he has more LP tokens)
        assertGt(bobRewards, aliceRewards, "Bob should have more rewards");

        // Rewards should be proportional to LP share
        uint256 totalLPTokens = lpToken.totalSupply();
        uint256 aliceShare = (aliceLPTokens * 1e18) / totalLPTokens;
        uint256 bobShare = (bobLPTokens * 1e18) / totalLPTokens;

        // Approximate check (within 5%)
        assertApproxEqRel(
            (aliceRewards * 1e18) / (aliceRewards + bobRewards),
            aliceShare,
            0.05e18,
            "Rewards should be proportional"
        );
    }

    function test_EarlyLPRewards() public {
        // Alice is early LP
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Fast forward 7 days
        vm.warp(block.timestamp + 7 days);

        // Generate fees
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        uint256 aliceRewards = feeManager.getPendingLPRewards(market, alice);
        assertGt(aliceRewards, 0, "Early LP should have rewards");
    }

    function test_LongTermLPRewards() public {
        // Alice adds liquidity early
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Generate fees
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // Check APR
        (, , uint256 apr) = feeManager.getLPInfo(market, alice);
        assertGt(apr, 0, "Should have positive APR");
    }

    function test_LPWithdrawal() public {
        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Generate some fees first
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        uint256 balanceBefore = collateral.balanceOf(alice);
        uint256 pendingRewardsBefore = feeManager.getPendingLPRewards(market, alice);

        // Remove liquidity (partial)
        vm.startPrank(alice);
        uint256 collateralReturned = CategoricalMarket(market).removeLiquidity(
            lpTokens / 2
        );
        vm.stopPrank();

        assertGt(collateralReturned, 0, "Should return collateral");
        assertGt(
            collateral.balanceOf(alice),
            balanceBefore,
            "Balance should increase"
        );

        // Should still have pending rewards from before
        // (but LP share is now halved)
        uint256 pendingRewardsAfter = feeManager.getPendingLPRewards(market, alice);
        assertLe(
            pendingRewardsAfter,
            pendingRewardsBefore,
            "Pending rewards should decrease (less LP share)"
        );
    }

    function test_LPRewardClaiming() public {
        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Generate fees
        for (uint256 i = 0; i < 15; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        uint256 balanceBefore = collateral.balanceOf(alice);
        uint256 pendingBefore = feeManager.getPendingLPRewards(market, alice);

        // Claim rewards
        vm.prank(alice);
        feeManager.claimLPRewards(market);

        assertEq(
            collateral.balanceOf(alice),
            balanceBefore + pendingBefore,
            "Balance should increase by pending rewards"
        );

        // Should have no pending rewards after claim
        uint256 pendingAfter = feeManager.getPendingLPRewards(market, alice);
        assertEq(pendingAfter, 0, "Should have no pending after claim");
    }

    function test_LPCompetition() public {
        // Multiple LPs compete
        address[] memory lps = new address[](5);
        lps[0] = alice;
        lps[1] = bob;
        lps[2] = carol;
        lps[3] = makeAddr("lp4");
        lps[4] = makeAddr("lp5");

        fundUser(lps[3], INITIAL_BALANCE);
        fundUser(lps[4], INITIAL_BALANCE);

        uint256[] memory lpTokens = new uint256[](5);

        // Each LP adds different amounts
        for (uint256 i = 0; i < lps.length; i++) {
            uint256 amount = (i + 1) * 10_000 * 1e18;
            vm.startPrank(lps[i]);
            collateral.approve(market, amount);
            lpTokens[i] = CategoricalMarket(market).addLiquidity(amount);
            vm.stopPrank();
        }

        // Generate significant trading volume
        for (uint256 i = 0; i < 50; i++) {
            address trader = makeAddr(string(abi.encodePacked("trader", i)));
            fundUser(trader, 10_000 * 1e18);

            vm.startPrank(trader);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(uint8(i % 2),  0, type(uint256).max);
            vm.stopPrank();
        }

        // Check rewards for all LPs
        uint256[] memory rewards = new uint256[](5);
        for (uint256 i = 0; i < lps.length; i++) {
            rewards[i] = feeManager.getPendingLPRewards(market, lps[i]);
            assertGt(rewards[i], 0, "Each LP should have rewards");
        }

        // LP with more tokens should have more rewards
        assertGt(rewards[4], rewards[0], "LP with more tokens should have more rewards");
    }

    function test_HighLiquidityLP_Bonus() public {
        // Add large liquidity (>10% of pool)
        vm.startPrank(alice);
        collateral.approve(market, 200_000 * 1e18);
        CategoricalMarket(market).addLiquidity(200_000 * 1e18);
        vm.stopPrank();

        // Generate fees
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // Check APR (should be boosted for high liquidity LP)
        (, , uint256 apr) = feeManager.getLPInfo(market, alice);
        assertGt(apr, 0, "Should have positive APR");
    }

    function test_LPLiquidityMatching() public {
        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, 50_000 * 1e18);
        uint256 lpTokens1 = CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // Market grows
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(bob);
            collateral.approve(market, 1000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // Add more liquidity later
        vm.startPrank(bob);
        collateral.approve(market, 50_000 * 1e18);
        uint256 lpTokens2 = CategoricalMarket(market).addLiquidity(50_000 * 1e18);
        vm.stopPrank();

        // First LP should still have proportional share
        uint256 totalLPTokens = lpToken.totalSupply();
        uint256 aliceShare = (lpTokens1 * 1e18) / totalLPTokens;
        uint256 bobShare = (lpTokens2 * 1e18) / totalLPTokens;

        // Shares should be proportional
        assertApproxEqRel(
            aliceShare,
            bobShare,
            0.01e18,
            "LP shares should be approximately equal for equal deposits"
        );
    }
}

