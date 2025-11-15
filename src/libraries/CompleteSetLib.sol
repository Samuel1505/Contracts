// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Errors} from "../utils/Errors.sol";

/**
 * @title CompleteSetLib
 * @notice Library for complete set mechanics in prediction markets
 * @dev A complete set = 1 share of EVERY outcome
 * Minting: 1 collateral → 1 share of each outcome
 * Burning: 1 share of each outcome → 1 collateral
 * This ensures prices sum to 1 and maintains market integrity
 */
library CompleteSetLib {
    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Validate complete set balances
     * @param balances Array of user's balances for each outcome
     * @return numSets Number of complete sets user can burn
     */
    function validateCompleteSet(
        uint256[] memory balances
    ) internal pure returns (uint256 numSets) {
        if (balances.length == 0) revert Errors.InvalidOutcomeCount();

        // Find minimum balance (that's how many complete sets we have)
        numSets = type(uint256).max;
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] < numSets) {
                numSets = balances[i];
            }
        }

        if (numSets == type(uint256).max) {
            numSets = 0;
        }

        return numSets;
    }

    /**
     * @notice Calculate cost to mint complete sets
     * @param amount Number of complete sets to mint
     * @return cost Cost in collateral (1:1 ratio)
     */
    function calculateMintCost(
        uint256 amount
    ) internal pure returns (uint256 cost) {
        if (amount == 0) revert Errors.ZeroAmount();
        // 1 complete set = 1 collateral
        return amount;
    }

    /**
     * @notice Calculate payout for burning complete sets
     * @param amount Number of complete sets to burn
     * @return payout Payout in collateral (1:1 ratio)
     */
    function calculateBurnPayout(
        uint256 amount
    ) internal pure returns (uint256 payout) {
        if (amount == 0) revert Errors.ZeroAmount();
        // 1 complete set = 1 collateral
        return amount;
    }

    /**
     * @notice Check if user has enough balance for complete sets
     * @param balances User's balances for each outcome
     * @param amount Number of complete sets needed
     * @return hasEnough True if user has enough
     */
    function hasCompleteSet(
        uint256[] memory balances,
        uint256 amount
    ) internal pure returns (bool hasEnough) {
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] < amount) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Calculate arbitrage opportunity
     * @dev If sum of individual outcome purchases < cost of complete set, arbitrage exists
     * @param prices Current prices of all outcomes
     * @return hasArbitrage True if arbitrage opportunity exists
     * @return costDifference Difference between complete set and individual purchases
     */
    function checkArbitrage(
        uint256[] memory prices
    ) internal pure returns (bool hasArbitrage, uint256 costDifference) {
        uint256 totalPrice = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            totalPrice += prices[i];
        }

        // Prices should sum to PRECISION (1.0)
        // If they don't, arbitrage exists
        if (totalPrice > PRECISION) {
            hasArbitrage = true;
            costDifference = totalPrice - PRECISION;
        } else if (totalPrice < PRECISION) {
            hasArbitrage = true;
            costDifference = PRECISION - totalPrice;
        } else {
            hasArbitrage = false;
            costDifference = 0;
        }

        return (hasArbitrage, costDifference);
    }
}
