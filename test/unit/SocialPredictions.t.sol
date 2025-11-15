// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SocialPredictions} from "../../src/core/SocialPredictions.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

/**
 * @title SocialPredictionsTest
 * @notice Tests for social features (predictions, comments, leaderboard)
 */
contract SocialPredictionsTest is TestHelpers {
    address market;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
    }

    // ============================================
    // PREDICTION TESTS
    // ============================================

    function test_MakePrediction() public {
        bytes32 metadataURI = stringToBytes32("QmPrediction123");
        uint8 outcome = 0;
        uint256 confidence = 75;

        vm.prank(alice);
        socialPredictions.makePrediction(market, outcome, confidence, metadataURI);

        SocialPredictions.UserPrediction memory prediction = socialPredictions
            .getUserPrediction(alice, market);

        assertEq(prediction.user, alice, "Should record user");
        assertEq(prediction.market, market, "Should record market");
        assertEq(prediction.predictedOutcome, outcome, "Should record outcome");
        assertEq(prediction.confidence, confidence, "Should record confidence");
        assertEq(prediction.metadataURI, metadataURI, "Should record metadata");
    }

    function test_MakePrediction_InvalidConfidence_Reverts() public {
        vm.expectRevert(Errors.InvalidParameter.selector);
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 101, stringToBytes32("test")); // > 100
    }

    function test_UpdatePredictionResult_Correct() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        // Update result
        vm.prank(owner); // Only owner can update
        socialPredictions.updatePredictionResult(alice, market, 0, 1000 * 1e18); // Outcome 0 wins, profit 1000

        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.correctPredictions, 1, "Should increment correct predictions");
        assertEq(stats.streak, 1, "Should increment streak");
        assertGt(stats.reputation, 0, "Should award reputation");
        assertGt(stats.totalProfit, 0, "Should track profit");
    }

    function test_UpdatePredictionResult_Incorrect() public {
        // Make prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        // Update result (outcome 1 wins, alice predicted 0)
        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 1, -500 * 1e18); // Loss

        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.correctPredictions, 0, "Should not increment correct");
        assertEq(stats.streak, 0, "Should reset streak");
        assertGt(stats.totalLoss, 0, "Should track loss");
    }

    function test_ConfidenceBonus() public {
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 100, stringToBytes32("test")); // Max confidence

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        (SocialPredictions.UserStats memory stats1, , ) = socialPredictions
            .getUserStats(alice);
        uint256 rep1 = stats1.reputation;

        // Lower confidence
        vm.prank(bob);
        socialPredictions.makePrediction(market, 0, 50, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(bob, market, 0, 0);

        (SocialPredictions.UserStats memory stats2, , ) = socialPredictions
            .getUserStats(bob);
        uint256 rep2 = stats2.reputation;

        // Higher confidence should give more reputation
        assertGt(rep1, rep2, "Higher confidence should give more reputation");
    }

    function test_StreakBonus() public {
        address market2 = createCategoricalMarket();

        // Make 5 correct predictions
        for (uint256 i = 0; i < 5; i++) {
            address currentMarket = i == 0 ? market : market2;
            vm.prank(alice);
            socialPredictions.makePrediction(currentMarket, 0, 80, stringToBytes32("test"));

            vm.prank(owner);
            socialPredictions.updatePredictionResult(alice, currentMarket, 0, 0);

            if (i < 4) {
                // Create new market for next prediction
                market2 = createSimpleMarket();
            }
        }

        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertGe(stats.streak, 5, "Should have streak >= 5");
        assertGt(stats.reputation, 1000, "Streak bonus should increase reputation"); // Base + streak bonus
    }

    function test_StreakResetOnIncorrect() public {
        // Make correct prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        // Make incorrect prediction
        address market2 = createSimpleMarket();
        vm.prank(alice);
        socialPredictions.makePrediction(market2, 0, 80, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market2, 1, 0); // Wrong outcome

        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.streak, 0, "Streak should reset on incorrect");
    }

    // ============================================
    // COMMENT TESTS
    // ============================================

    function test_PostComment() public {
        bytes32 metadataURI = stringToBytes32("QmComment123");

        vm.prank(alice);
        socialPredictions.postComment(market, metadataURI);

        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);

        assertEq(comments.length, 1, "Should have one comment");
        assertEq(comments[0].author, alice, "Should record author");
        assertEq(comments[0].market, market, "Should record market");
        assertEq(comments[0].metadataURI, metadataURI, "Should record metadata");
    }

    function test_PostComment_InvalidMarket_Reverts() public {
        vm.expectRevert(Errors.InvalidAddress.selector);
        vm.prank(alice);
        socialPredictions.postComment(address(0), stringToBytes32("test"));
    }

    function test_VoteOnComment_Upvote() public {
        // Post comment
        vm.prank(alice);
        socialPredictions.postComment(market, stringToBytes32("test"));

        // Upvote
        vm.prank(bob);
        socialPredictions.voteOnComment(market, 0, true);

        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);

        assertEq(comments[0].upvotes, 1, "Should increment upvotes");
        assertEq(comments[0].downvotes, 0, "Should not increment downvotes");
    }

    function test_VoteOnComment_Downvote() public {
        vm.prank(alice);
        socialPredictions.postComment(market, stringToBytes32("test"));

        vm.prank(bob);
        socialPredictions.voteOnComment(market, 0, false);

        SocialPredictions.Comment[] memory comments = socialPredictions
            .getMarketComments(market, 0, 10);

        assertEq(comments[0].downvotes, 1, "Should increment downvotes");
        assertEq(comments[0].upvotes, 0, "Should not increment upvotes");
    }

    function test_VoteOnComment_Twice_Reverts() public {
        vm.prank(alice);
        socialPredictions.postComment(market, stringToBytes32("test"));

        vm.prank(bob);
        socialPredictions.voteOnComment(market, 0, true);

        vm.expectRevert(Errors.InvalidParameter.selector);
        vm.prank(bob);
        socialPredictions.voteOnComment(market, 0, false); // Try to vote again
    }

    function test_GetMarketComments_Pagination() public {
        // Post multiple comments
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            socialPredictions.postComment(market, stringToBytes32("test"));
        }

        // Get first 2
        SocialPredictions.Comment[] memory comments1 = socialPredictions
            .getMarketComments(market, 0, 2);
        assertEq(comments1.length, 2, "Should return 2 comments");

        // Get next 2
        SocialPredictions.Comment[] memory comments2 = socialPredictions
            .getMarketComments(market, 2, 2);
        assertEq(comments2.length, 2, "Should return 2 more comments");

        // Get remaining
        SocialPredictions.Comment[] memory comments3 = socialPredictions
            .getMarketComments(market, 4, 10);
        assertEq(comments3.length, 1, "Should return remaining comments");
    }

    // ============================================
    // LEADERBOARD TESTS
    // ============================================

    function test_Leaderboard_Ranking() public {
        // Alice makes correct prediction
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 90, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        // Bob makes correct prediction with lower confidence
        vm.prank(bob);
        socialPredictions.makePrediction(market, 0, 50, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(bob, market, 0, 0);

        (
            address[] memory users,
            uint256[] memory reputations,
            uint256[] memory winRates
        ) = socialPredictions.getLeaderboard(10);

        // Both should be on leaderboard
        assertGe(users.length, 1, "Should have users on leaderboard");

        // Alice should have higher reputation
        (SocialPredictions.UserStats memory aliceStats, , ) = socialPredictions
            .getUserStats(alice);
        (SocialPredictions.UserStats memory bobStats, , ) = socialPredictions
            .getUserStats(bob);

        assertGt(aliceStats.reputation, bobStats.reputation, "Alice should have more reputation");
    }

    function test_Leaderboard_MaxSize() public {
        // Create many users with predictions
        for (uint256 i = 0; i < 150; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            address currentMarket = createSimpleMarket();

            vm.prank(user);
            socialPredictions.makePrediction(currentMarket, 0, 80, stringToBytes32("test"));

            vm.prank(owner);
            socialPredictions.updatePredictionResult(user, currentMarket, 0, 0);
        }

        (
            address[] memory users,
            ,
        ) = socialPredictions.getLeaderboard(200);

        // Should be capped at MAX_LEADERBOARD_SIZE
        assertLe(users.length, 100, "Leaderboard should be capped at 100");
    }

    function test_GetUserStats() public {
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        (SocialPredictions.UserStats memory stats, uint256 winRate, uint256 rank) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.totalPredictions, 1, "Should track total predictions");
        assertEq(stats.correctPredictions, 1, "Should track correct predictions");
        assertEq(winRate, 10000, "Win rate should be 100%"); // 10000 = 100% in basis points
        assertGt(rank, 0, "Should have rank if on leaderboard");
    }

    function test_GetUserPredictionHistory() public {
        address market2 = createSimpleMarket();
        address market3 = createSimpleMarket();

        // Make multiple predictions
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test1"));

        vm.prank(alice);
        socialPredictions.makePrediction(market2, 1, 70, stringToBytes32("test2"));

        vm.prank(alice);
        socialPredictions.makePrediction(market3, 0, 90, stringToBytes32("test3"));

        SocialPredictions.UserPrediction[] memory history = socialPredictions
            .getUserPredictionHistory(alice, 10);

        assertEq(history.length, 3, "Should return all predictions");
        // Should be in reverse chronological order (most recent first)
        assertEq(history[0].market, market3, "Most recent should be first");
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_MakePrediction_InvalidMarket_Reverts() public {
        vm.expectRevert(Errors.InvalidAddress.selector);
        vm.prank(alice);
        socialPredictions.makePrediction(address(0), 0, 80, stringToBytes32("test"));
    }

    function test_VoteOnComment_InvalidCommentId_Reverts() public {
        vm.expectRevert(Errors.InvalidParameter.selector);
        vm.prank(alice);
        socialPredictions.voteOnComment(market, 999, true);
    }

    function test_UpdatePredictionResult_NoPrediction() public {
        // No prediction made, should not revert but do nothing
        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        (SocialPredictions.UserStats memory stats, , ) = socialPredictions
            .getUserStats(alice);

        assertEq(stats.totalPredictions, 0, "Should not change stats if no prediction");
    }

    function test_ReputationPenalty() public {
        // Give alice some reputation
        vm.prank(alice);
        socialPredictions.makePrediction(market, 0, 80, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market, 0, 0);

        (SocialPredictions.UserStats memory statsBefore, , ) = socialPredictions
            .getUserStats(alice);
        uint256 repBefore = statsBefore.reputation;

        // Make incorrect prediction
        address market2 = createSimpleMarket();
        vm.prank(alice);
        socialPredictions.makePrediction(market2, 0, 80, stringToBytes32("test"));

        vm.prank(owner);
        socialPredictions.updatePredictionResult(alice, market2, 1, 0);

        (SocialPredictions.UserStats memory statsAfter, , ) = socialPredictions
            .getUserStats(alice);
        uint256 repAfter = statsAfter.reputation;

        // Reputation should decrease
        if (repBefore > 50) {
            assertLt(repAfter, repBefore, "Reputation should decrease on incorrect prediction");
        }
    }
}

