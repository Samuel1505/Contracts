// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Errors
 * @notice Custom errors for gas-efficient reverts across the protocol
 */
library Errors {
    // Market Errors
    error MarketAlreadyResolved();
    error MarketNotResolved();
    error MarketNotActive();
    error MarketCancelled();
    error InvalidMarketStatus();
    error ResolutionTimeNotReached();
    error ResolutionTimePassed();
    
    // Outcome Errors
    error InvalidOutcome();
    error InvalidOutcomeCount();
    error NoWinningOutcome();
    
    // Trading Errors
    error InsufficientBalance();
    error InsufficientShares();
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InvalidAmount();
    error ZeroAmount();
    error SlippageExceeded();
    
    // Liquidity Errors
    error NoLPTokens();
    error InvalidLPAmount();
    error LiquidityLocked();
    
    // Access Control Errors
    error Unauthorized();
    error OnlyOracle();
    error OnlyFactory();
    error OnlyMarket();
    error OnlyAdmin();
    
    // Claim Errors
    error NothingToClaim();
    error AlreadyClaimed();
    error NotWinner();
    
    // Initialization Errors
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidInitialization();
    
    // Fee Errors
    error InvalidFeePercent();
    error FeeTransferFailed();
    
    // General Errors
    error InvalidAddress();
    error InvalidParameter();
    error ArrayLengthMismatch();
}

