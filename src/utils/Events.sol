// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICategoricalMarket} from "../interfaces/ICategoricalMarket.sol";

/**
 * @title Events
 * @notice Centralized event definitions for the PulseDelta protocol
 */
library Events {
    // ============================================
    // MARKET EVENTS
    // ============================================

    /**
     * @notice Emitted when a market is initialized
     * @param metadataURI IPFS CID containing market metadata (question, description, outcomes, images)
     * @param numOutcomes Number of outcomes in the market
     * @param resolutionTime When the market can be resolved
     * @param oracle Address of the oracle resolver
     */
    event MarketInitialized(
        bytes32 indexed metadataURI,
        uint256 numOutcomes,
        uint256 resolutionTime,
        address indexed oracle
    );

    /**
     * @notice Emitted when shares are purchased
     * @param user Address of the buyer
     * @param outcome Index of the outcome purchased
     * @param shares Amount of shares received
     * @param cost Amount of collateral spent
     */
    event SharesPurchased(
        address indexed user,
        uint8 indexed outcome,
        uint256 shares,
        uint256 cost
    );

    /**
     * @notice Emitted when shares are sold
     * @param user Address of the seller
     * @param outcome Index of the outcome sold
     * @param shares Amount of shares sold
     * @param payout Amount of collateral received
     */
    event SharesSold(
        address indexed user,
        uint8 indexed outcome,
        uint256 shares,
        uint256 payout
    );

    /**
     * @notice Emitted when liquidity is added to a market
     * @param provider Address of the liquidity provider
     * @param amount Amount of collateral added
     * @param lpTokens Amount of LP tokens minted
     */
    event LiquidityAdded(
        address indexed provider,
        uint256 amount,
        uint256 lpTokens
    );

    /**
     * @notice Emitted when liquidity is removed from a market
     * @param provider Address of the liquidity provider
     * @param lpTokens Amount of LP tokens burned
     * @param amount Amount of collateral returned
     */
    event LiquidityRemoved(
        address indexed provider,
        uint256 lpTokens,
        uint256 amount
    );

    /**
     * @notice Emitted when a market is resolved
     * @param winningOutcome Index of the winning outcome
     * @param timestamp Time of resolution
     */
    event MarketResolved(uint8 indexed winningOutcome, uint256 timestamp);

    /**
     * @notice Emitted when winnings are claimed
     * @param user Address of the claimant
     * @param amount Amount of winnings claimed
     */
    event WinningsClaimed(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a market is cancelled
     * @param timestamp Time of cancellation
     */
    event MarketCancelled(uint256 timestamp);

    // ============================================
    // FACTORY EVENTS
    // ============================================

    /**
     * @notice Emitted when a new market is created
     * @param market Address of the new market
     * @param metadataURI IPFS CID containing market metadata
     * @param numOutcomes Number of outcomes
     * @param resolutionTime When the market can be resolved
     * @param creator Address that created the market
     */
    event MarketCreated(
        address indexed market,
        bytes32 indexed metadataURI,
        uint256 numOutcomes,
        uint256 resolutionTime,
        address indexed creator
    );

    /**
     * @notice Emitted when factory admin is updated
     * @param oldAdmin Previous admin address
     * @param newAdmin New admin address
     */
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @notice Emitted when oracle resolver is updated
     * @param oldOracle Previous oracle address
     * @param newOracle New oracle address
     */
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ============================================
    // FEE ROUTER EVENTS
    // ============================================

    /**
     * @notice Emitted when fees are collected from a market
     * @param market Address of the market
     * @param amount Amount of fees collected
     */
    event FeeCollected(address indexed market, uint256 amount);

    /**
     * @notice Emitted when fees are withdrawn to treasury
     * @param treasury Address of the treasury
     * @param amount Amount of fees withdrawn
     */
    event FeesWithdrawn(address indexed treasury, uint256 amount);

    /**
     * @notice Emitted when treasury address is updated
     * @param oldTreasury Previous treasury address
     * @param newTreasury New treasury address
     */
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    /**
     * @notice Emitted when fee percentage is updated
     * @param oldPercent Previous fee percentage
     * @param newPercent New fee percentage
     */
    event FeePercentUpdated(uint256 oldPercent, uint256 newPercent);

    /**
     * @notice Emitted when a market is registered with the fee router
     * @param market Address of the registered market
     */
    event MarketRegistered(address indexed market);
}
