// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title SocialPredictions
 * @notice Social features for prediction markets (IPFS-optimized)
 * @dev Includes: User predictions, comments, leaderboards, reputation
 * All text content stored in IPFS, only hashes on-chain for gas efficiency
 */
contract SocialPredictions is Ownable {
    struct UserPrediction {
        address user;
        address market;
        uint8 predictedOutcome;
        bytes32 metadataURI; // IPFS CID containing reasoning
        uint256 timestamp;
        uint256 confidence; // 0-100
    }

    struct Comment {
        address author;
        address market;
        bytes32 metadataURI; // IPFS CID containing comment content
        uint256 timestamp;
        uint256 upvotes;
        uint256 downvotes;
    }

    struct UserStats {
        uint256 totalPredictions;
        uint256 correctPredictions;
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 reputation;
        uint256 streak;
    }

    // Prediction tracking
    mapping(address => mapping(address => UserPrediction))
        public userPredictions; // user => market => prediction
    mapping(address => UserPrediction[]) public userPredictionHistory;

    // Comments
    mapping(address => Comment[]) public marketComments; // market => comments
    mapping(bytes32 => bool) public hasVoted; // keccak256(user, commentId) => voted

    // Leaderboard
    mapping(address => UserStats) public userStats;
    address[] public leaderboard;
    uint256 public constant MAX_LEADERBOARD_SIZE = 100;

    // Reputation multipliers
    uint256 private constant REPUTATION_BASE = 1000;
    uint256 private constant CORRECT_PREDICTION_POINTS = 100;
    uint256 private constant STREAK_BONUS_MULTIPLIER = 10;

    // Events (IPFS CIDs indexed for efficient retrieval)
    event PredictionMade(
        address indexed user,
        address indexed market,
        uint8 outcomeIndex,
        uint256 confidence,
        bytes32 metadataURI // IPFS CID containing prediction reasoning
    );

    event CommentPosted(
        address indexed author,
        address indexed market,
        uint256 commentId,
        bytes32 metadataURI // IPFS CID containing comment content
    );

    event CommentVoted(
        address indexed voter,
        address indexed market,
        uint256 commentId,
        bool isUpvote
    );

    event ReputationUpdated(
        address indexed user,
        uint256 newReputation,
        int256 change
    );

    constructor() Ownable(msg.sender) {}

    // ============================================
    // PREDICTION FUNCTIONS
    // ============================================

    /**
     * @notice Make a prediction (non-financial)
     * @param market Market address
     * @param outcomeIndex Predicted outcome
     * @param confidence Confidence level (0-100)
     * @param metadataURI IPFS CID containing prediction reasoning
     */
    function makePrediction(
        address market,
        uint8 outcomeIndex,
        uint256 confidence,
        bytes32 metadataURI
    ) external {
        if (market == address(0)) revert Errors.InvalidAddress();
        if (confidence > 100) revert Errors.InvalidParameter();

        UserPrediction memory prediction = UserPrediction({
            user: msg.sender,
            market: market,
            predictedOutcome: outcomeIndex,
            metadataURI: metadataURI,
            timestamp: block.timestamp,
            confidence: confidence
        });

        userPredictions[msg.sender][market] = prediction;
        userPredictionHistory[msg.sender].push(prediction);
        userStats[msg.sender].totalPredictions++;

        emit PredictionMade(
            msg.sender,
            market,
            outcomeIndex,
            confidence,
            metadataURI
        );
    }

    /**
     * @notice Update prediction result after market resolution
     * @param user User address
     * @param market Market address
     * @param winningOutcome Actual winning outcome
     * @param profit Profit made (0 if not traded)
     */
    function updatePredictionResult(
        address user,
        address market,
        uint8 winningOutcome,
        int256 profit
    ) external onlyOwner {
        UserPrediction memory prediction = userPredictions[user][market];
        if (prediction.timestamp == 0) return; // No prediction made

        UserStats storage stats = userStats[user];

        // Check if prediction was correct
        if (prediction.predictedOutcome == winningOutcome) {
            stats.correctPredictions++;
            stats.streak++;

            // Award reputation points
            uint256 points = CORRECT_PREDICTION_POINTS;

            // Confidence bonus
            points += (prediction.confidence * CORRECT_PREDICTION_POINTS) / 100;

            // Streak bonus
            if (stats.streak >= 5) {
                points += stats.streak * STREAK_BONUS_MULTIPLIER;
            }

            stats.reputation += points;

            emit ReputationUpdated(user, stats.reputation, int256(points));
        } else {
            // Reset streak on incorrect prediction
            if (stats.streak > 0) {
                stats.streak = 0;
            }

            // Small reputation penalty
            if (stats.reputation > 50) {
                stats.reputation -= 50;
                emit ReputationUpdated(user, stats.reputation, -50);
            }
        }

        // Update profit/loss
        if (profit > 0) {
            stats.totalProfit += uint256(profit);
        } else if (profit < 0) {
            stats.totalLoss += uint256(-profit);
        }

        // Update leaderboard
        _updateLeaderboard(user);
    }

    // ============================================
    // COMMENT FUNCTIONS
    // ============================================

    /**
     * @notice Post a comment on a market
     * @param market Market address
     * @param metadataURI IPFS CID containing comment content
     */
    function postComment(address market, bytes32 metadataURI) external {
        if (market == address(0)) revert Errors.InvalidAddress();
        if (metadataURI == bytes32(0)) revert Errors.InvalidParameter();

        Comment memory comment = Comment({
            author: msg.sender,
            market: market,
            metadataURI: metadataURI,
            timestamp: block.timestamp,
            upvotes: 0,
            downvotes: 0
        });

        marketComments[market].push(comment);
        uint256 commentId = marketComments[market].length - 1;

        emit CommentPosted(msg.sender, market, commentId, metadataURI);
    }

    /**
     * @notice Vote on a comment
     * @param market Market address
     * @param commentId Comment ID
     * @param isUpvote True for upvote, false for downvote
     */
    function voteOnComment(
        address market,
        uint256 commentId,
        bool isUpvote
    ) external {
        if (commentId >= marketComments[market].length)
            revert Errors.InvalidParameter();

        bytes32 voteKey = keccak256(
            abi.encodePacked(msg.sender, market, commentId)
        );
        if (hasVoted[voteKey]) revert Errors.InvalidParameter(); // Already voted

        hasVoted[voteKey] = true;

        if (isUpvote) {
            marketComments[market][commentId].upvotes++;
        } else {
            marketComments[market][commentId].downvotes++;
        }

        emit CommentVoted(msg.sender, market, commentId, isUpvote);
    }

    // ============================================
    // LEADERBOARD & STATS
    // ============================================

    /**
     * @notice Get top users from leaderboard
     * @param limit Number of users to return
     * @return users Array of top user addresses
     * @return reputations Array of reputation scores
     * @return winRates Array of win rates (in basis points)
     */
    function getLeaderboard(
        uint256 limit
    )
        external
        view
        returns (
            address[] memory users,
            uint256[] memory reputations,
            uint256[] memory winRates
        )
    {
        uint256 size = limit > leaderboard.length ? leaderboard.length : limit;

        users = new address[](size);
        reputations = new uint256[](size);
        winRates = new uint256[](size);

        for (uint256 i = 0; i < size; i++) {
            users[i] = leaderboard[i];
            reputations[i] = userStats[leaderboard[i]].reputation;

            UserStats memory stats = userStats[leaderboard[i]];
            if (stats.totalPredictions > 0) {
                winRates[i] =
                    (stats.correctPredictions * 10000) /
                    stats.totalPredictions;
            }
        }

        return (users, reputations, winRates);
    }

    /**
     * @notice Get user stats
     * @param user User address
     * @return stats User statistics
     * @return winRate Win rate in basis points
     * @return rank User's rank on leaderboard (0 if not ranked)
     */
    function getUserStats(
        address user
    )
        external
        view
        returns (UserStats memory stats, uint256 winRate, uint256 rank)
    {
        stats = userStats[user];

        if (stats.totalPredictions > 0) {
            winRate =
                (stats.correctPredictions * 10000) /
                stats.totalPredictions;
        }

        // Find rank
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i] == user) {
                rank = i + 1;
                break;
            }
        }

        return (stats, winRate, rank);
    }

    /**
     * @notice Get user's prediction for a market
     * @param user User address
     * @param market Market address
     * @return prediction User's prediction
     */
    function getUserPrediction(
        address user,
        address market
    ) external view returns (UserPrediction memory prediction) {
        return userPredictions[user][market];
    }

    /**
     * @notice Get all comments for a market
     * @param market Market address
     * @param offset Starting index
     * @param limit Number of comments to return
     * @return comments Array of comments
     */
    function getMarketComments(
        address market,
        uint256 offset,
        uint256 limit
    ) external view returns (Comment[] memory comments) {
        uint256 totalComments = marketComments[market].length;
        if (offset >= totalComments) {
            return new Comment[](0);
        }

        uint256 end = offset + limit;
        if (end > totalComments) {
            end = totalComments;
        }

        uint256 resultSize = end - offset;
        comments = new Comment[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            comments[i] = marketComments[market][offset + i];
        }

        return comments;
    }

    /**
     * @notice Get user's prediction history
     * @param user User address
     * @param limit Number of predictions to return
     * @return predictions Array of user's predictions
     */
    function getUserPredictionHistory(
        address user,
        uint256 limit
    ) external view returns (UserPrediction[] memory predictions) {
        uint256 totalPredictions = userPredictionHistory[user].length;
        uint256 size = limit > totalPredictions ? totalPredictions : limit;

        predictions = new UserPrediction[](size);

        // Return most recent first
        for (uint256 i = 0; i < size; i++) {
            predictions[i] = userPredictionHistory[user][
                totalPredictions - 1 - i
            ];
        }

        return predictions;
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @dev Update leaderboard with user's new stats
     */
    function _updateLeaderboard(address user) internal {
        // Remove user from current position
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i] == user) {
                // Shift array
                for (uint256 j = i; j < leaderboard.length - 1; j++) {
                    leaderboard[j] = leaderboard[j + 1];
                }
                leaderboard.pop();
                break;
            }
        }

        // Find correct position based on reputation
        uint256 reputation = userStats[user].reputation;
        uint256 insertIndex = leaderboard.length;

        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (reputation > userStats[leaderboard[i]].reputation) {
                insertIndex = i;
                break;
            }
        }

        // Insert at correct position (if within top MAX_LEADERBOARD_SIZE)
        if (insertIndex < MAX_LEADERBOARD_SIZE) {
            leaderboard.push(address(0)); // Add empty slot

            // Shift elements
            for (uint256 i = leaderboard.length - 1; i > insertIndex; i--) {
                leaderboard[i] = leaderboard[i - 1];
            }

            leaderboard[insertIndex] = user;

            // Trim if over max size
            if (leaderboard.length > MAX_LEADERBOARD_SIZE) {
                leaderboard.pop();
            }
        }
    }
}
