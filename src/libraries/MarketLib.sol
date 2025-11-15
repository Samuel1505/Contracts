// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MarketLib
 * @notice Helper library for market-related calculations and utilities
 */
library MarketLib {
    /**
     * @notice Calculate potential winnings for a user
     * @param shares Array of user's shares for each outcome
     * @param winningOutcome Index of the winning outcome
     * @return potentialWinnings Amount user can claim
     */
    function calculateWinnings(
        uint256[] memory shares,
        uint8 winningOutcome
    ) internal pure returns (uint256 potentialWinnings) {
        if (winningOutcome >= shares.length) {
            return 0;
        }
        return shares[winningOutcome];
    }

    /**
     * @notice Calculate the total value of a user's position across all outcomes
     * @param shares Array of user's shares
     * @param prices Current prices for all outcomes
     * @return totalValue Total market value of position
     */
    function calculatePositionValue(
        uint256[] memory shares,
        uint256[] memory prices
    ) internal pure returns (uint256 totalValue) {
        require(shares.length == prices.length, "Array length mismatch");

        for (uint256 i = 0; i < shares.length; i++) {
            totalValue += (shares[i] * prices[i]) / 1e18;
        }

        return totalValue;
    }

    /**
     * @notice Check if a market resolution time has been reached
     * @param resolutionTime The scheduled resolution timestamp
     * @return canResolve True if current time >= resolution time
     */
    function canResolveMarket(uint256 resolutionTime) internal view returns (bool canResolve) {
        return block.timestamp >= resolutionTime;
    }

    /**
     * @notice Calculate time remaining until resolution
     * @param resolutionTime The scheduled resolution timestamp
     * @return timeRemaining Seconds until resolution (0 if already passed)
     */
    function timeUntilResolution(uint256 resolutionTime)
        internal
        view
        returns (uint256 timeRemaining)
    {
        if (block.timestamp >= resolutionTime) {
            return 0;
        }
        return resolutionTime - block.timestamp;
    }

    /**
     * @notice Validate outcome names array
     * @param outcomeNames Array of outcome name strings
     * @return isValid True if valid (2+ outcomes, non-empty strings)
     */
    function validateOutcomeNames(string[] memory outcomeNames)
        internal
        pure
        returns (bool isValid)
    {
        if (outcomeNames.length < 2) {
            return false;
        }

        for (uint256 i = 0; i < outcomeNames.length; i++) {
            if (bytes(outcomeNames[i]).length == 0) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Validate resolution time
     * @param resolutionTime The proposed resolution timestamp
     * @param minDuration Minimum duration from now (in seconds)
     * @return isValid True if valid
     */
    function validateResolutionTime(uint256 resolutionTime, uint256 minDuration)
        internal
        view
        returns (bool isValid)
    {
        return resolutionTime > block.timestamp + minDuration;
    }
}

