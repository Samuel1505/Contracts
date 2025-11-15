// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {SocialPredictions} from "../../src/core/SocialPredictions.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title SocialIntegrationTest
 * @notice Integration tests for social features + trading
 */
contract SocialIntegrationTest is TestHelpers {
    address market;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
    }

    function test_MakePredictionThenTrade() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 85, stringToBytes32("test"));

        // Then trade on that prediction
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Check prediction still exists
        SocialPredictions.UserPrediction memory prediction = socialPredictions
            .getUserPrediction(alice, market);

        assertEq(prediction.predictedOutcome, 0, "Prediction should remain");
        assertEq(prediction.confidence, 85, "Confidence should remain");
    }

    function test_TradeThenMakePrediction() public {
        // Trade first
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Then make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 90, stringToBytes32("test"));

        // Both should exist
        SocialPredictions.UserPrediction memory prediction = socialPredictions
            .getUserPrediction(alice, market);

        assertEq(prediction.predictedOutcome, 0, "Prediction should be recorded");
    }

    function test_PredictionResultWithProfit() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        // Trade
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Resolve market
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(0);

        // Claim winnings
        vm.prank(alice);
        uint256 winnings = CategoricalMarket(market).claimWinnings();

        // Update prediction result with profit
        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, int256(winnings));

        // Check stats
        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.correctPredictions, 1, "Should track correct prediction");
        assertGt(stats.totalProfit, 0, "Should track profit");
        assertGt(stats.reputation, 0, "Should award reputation");
    }

    function test_PredictionResultWithLoss() public {
        // Make prediction on outcome 0
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        // Trade on outcome 0
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Resolve market with outcome 1 winning
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(market)
            .getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(1);

        // Alice loses - shares are worthless
        uint256 loss = 5000 * 1e18; // Cost of shares

        // Update prediction result with loss
        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 1, -int256(loss));

        // Check stats
        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.correctPredictions, 0, "Should not track as correct");
        assertGt(stats.totalLoss, 0, "Should track loss");
        assertEq(stats.streak, 0, "Streak should reset");
    }

    function test_CommentsOnMarket() public {
        // Post comment before trading
        vm.prank(alice);
        socialPredictions.postComment(market, stringToBytes32("Great market!"));

        // Trade
        vm.startPrank(bob);
        collateral.approve(market, 5000 * 1e18);
        CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
        vm.stopPrank();

        // Post another comment after trading
        vm.prank(bob);
        socialPredictions.postComment(market, stringToBytes32("Just bought outcome 0"));

        // Check comments
        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);

        assertEq(comments.length, 2, "Should have 2 comments");
    }

    function test_CommentVoting() public {
        // Post comment
        vm.prank(alice);
        socialPredictions.postComment(market, stringToBytes32("My analysis"));

        // Multiple users vote
        vm.prank(bob);
        socialPredictions.voteOnComment(market, 0, true);

        vm.prank(carol);
        socialPredictions.voteOnComment(market, 0, true);

        address user4 = makeAddr("user4");
        vm.prank(user4);
        socialPredictions.voteOnComment(market, 0, false);

        // Check votes
        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);

        assertEq(comments[0].upvotes, 2, "Should have 2 upvotes");
        assertEq(comments[0].downvotes, 1, "Should have 1 downvote");
    }

    function test_LeaderboardWithTrading() public {
        address market2 = createSimpleMarket();

        // Alice makes correct predictions and trades
        for (uint256 i = 0; i < 2; i++) {
            address currentMarket = i == 0 ? market : market2;

            vm.prank(alice);
            socialPredictions.makePrediction(currentMarket, 0, 90, stringToBytes32("test"));

            vm.startPrank(alice);
            collateral.approve(currentMarket, 5000 * 1e18);
            CategoricalMarket(currentMarket).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();

            // Resolve
            (CategoricalMarket.MarketInfo memory marketInfo, , ) = CategoricalMarket(
                currentMarket
            ).getMarketState();
            vm.warp(marketInfo.resolutionTime);

            vm.prank(oracle);
            CategoricalMarket(currentMarket).resolveMarket(0);

            vm.prank(alice);
            uint256 winnings = CategoricalMarket(currentMarket).claimWinnings();

            vm.prank(owner);
            socialPredictions.updatePredictionResult(
                alice,
                currentMarket,
                0,
                int256(winnings)
            );
        }

        // Bob makes incorrect predictions
        address market3 = createSimpleMarket();

        vm.prank(bob);
        socialPredictions.makePrediction(market3, 0, 70, stringToBytes32("test"));

        (CategoricalMarket.MarketInfo memory marketInfo3, , ) = CategoricalMarket(market3)
            .getMarketState();
        vm.warp(marketInfo3.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market3).resolveMarket(1); // Wrong outcome

        vm.prank(owner);
        socialPredictions.updatePredictionResult(bob, market3, 1, 0);

        // Check leaderboard
        (
            address[] memory users,
            uint256[] memory reputations,
        ) = socialPredictions.getLeaderboard(10);

        // Alice should have higher reputation
        (SocialPredictions.UserStats memory aliceStats, , ) = socialPredictions
            .getUserStats(alice);
        (SocialPredictions.UserStats memory bobStats, , ) = socialPredictions
            .getUserStats(bob);

        assertGt(aliceStats.reputation, bobStats.reputation, "Alice should rank higher");
    }

    function test_SocialFeaturesDontAffectTrading() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        // Post comment
        vm.prank(bob);
        socialPredictions.postComment(market, stringToBytes32("Comment"));

        // Trading should work normally
        vm.startPrank(alice);
        collateral.approve(market, 5000 * 1e18);
        (uint256 shares, uint256 cost) = CategoricalMarket(market).buyShares(
            0,
            0,
            type(uint256).max
        );
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertGt(cost, 0, "Should pay cost");

        // Social features should still work
        SocialPredictions.UserPrediction memory prediction = socialPredictions
            .getUserPrediction(alice, market);
        assertEq(prediction.predictedOutcome, 0, "Prediction should remain");

        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);
        assertEq(comments.length, 1, "Comment should remain");
    }

    function test_PredictionHistoryWithMultipleTrades() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 85, stringToBytes32("test"));

        // Make multiple trades
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(alice);
            collateral.approve(market, 2000 * 1e18);
            CategoricalMarket(market).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();
        }

        // Prediction should still exist
        SocialPredictions.UserPrediction memory prediction = socialPredictions
            .getUserPrediction(alice, market);

        assertEq(prediction.predictedOutcome, 0, "Prediction should persist");
        assertEq(prediction.confidence, 85, "Confidence should persist");
    }

    function test_StreakWithCorrectTrades() public {
        // Create multiple markets
        for (uint256 i = 0; i < 5; i++) {
            address currentMarket = i == 0 ? market : createSimpleMarket();

            // Make prediction
            vm.prank(alice);
            socialPredictions.makePrediction(
                currentMarket,
                0,
                80,
                stringToBytes32("test")
            );

            // Trade
            vm.startPrank(alice);
            collateral.approve(currentMarket, 3000 * 1e18);
            CategoricalMarket(currentMarket).buyShares(0,  0, type(uint256).max);
            vm.stopPrank();

            // Resolve and update
            (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
                currentMarket
            ).getMarketState();
            vm.warp(info.resolutionTime);

            vm.prank(oracle);
            CategoricalMarket(currentMarket).resolveMarket(0);

            vm.prank(alice);
            uint256 winnings = CategoricalMarket(currentMarket).claimWinnings();

            vm.prank(owner);
            socialPredictions.updatePredictionResult(
                alice,
                currentMarket,
                0,
                int256(winnings)
            );
        }

        // Check streak
        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertGe(stats.streak, 5, "Should have streak >= 5");
        assertEq(stats.correctPredictions, 5, "Should have 5 correct predictions");
        assertGt(stats.reputation, 2000, "Should have boosted reputation from streak");
    }
}

