// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title DynamicFeeLib
 * @notice Library for calculating dynamic fees based on market conditions
 * @dev Fees adjust based on:
 * - Trading volume (higher volume = lower fees)
 * - Liquidity depth (lower liquidity = higher fees)
 * - Market age (newer markets = higher fees)
 */
library DynamicFeeLib {
    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant PRECISION = 1e18;

    // Fee bounds
    uint256 private constant MIN_FEE_BPS = 10; // 0.1%
    uint256 private constant MAX_FEE_BPS = 100; // 1.0%
    uint256 private constant BASE_FEE_BPS = 30; // 0.3% base fee

    // Volume thresholds for fee tiers
    uint256 private constant HIGH_VOLUME_THRESHOLD = 1_000_000 * 1e18; // 1M
    uint256 private constant MED_VOLUME_THRESHOLD = 100_000 * 1e18; // 100K

    // Liquidity thresholds
    uint256 private constant HIGH_LIQUIDITY_THRESHOLD = 500_000 * 1e18; // 500K
    uint256 private constant LOW_LIQUIDITY_THRESHOLD = 10_000 * 1e18; // 10K

    /**
     * @notice Calculate dynamic fee based on market conditions
     * @param totalVolume Total volume traded in the market
     * @param liquidity Current liquidity in the market
     * @param marketAge Age of market in seconds
     * @return totalFeeBps Total fee in basis points
     * @return protocolFeeBps Protocol fee portion
     * @return lpFeeBps LP fee portion
     */
    function calculateDynamicFee(
        uint256 totalVolume,
        uint256 liquidity,
        uint256 marketAge
    )
        internal
        pure
        returns (uint256 totalFeeBps, uint256 protocolFeeBps, uint256 lpFeeBps)
    {
        uint256 baseFee = BASE_FEE_BPS;

        // Volume adjustment (higher volume = lower fee)
        int256 volumeAdjustment = 0;
        if (totalVolume >= HIGH_VOLUME_THRESHOLD) {
            volumeAdjustment = -10; // -0.1%
        } else if (totalVolume >= MED_VOLUME_THRESHOLD) {
            volumeAdjustment = -5; // -0.05%
        }

        // Liquidity adjustment (lower liquidity = higher fee for risk)
        int256 liquidityAdjustment = 0;
        if (liquidity < LOW_LIQUIDITY_THRESHOLD) {
            liquidityAdjustment = 20; // +0.2%
        } else if (liquidity < HIGH_LIQUIDITY_THRESHOLD) {
            liquidityAdjustment = 10; // +0.1%
        }

        // Age adjustment (new markets have higher fees)
        int256 ageAdjustment = 0;
        if (marketAge < 1 days) {
            ageAdjustment = 15; // +0.15%
        } else if (marketAge < 7 days) {
            ageAdjustment = 5; // +0.05%
        }

        // Calculate total fee
        int256 adjustedFee = int256(baseFee) +
            volumeAdjustment +
            liquidityAdjustment +
            ageAdjustment;

        // Bound the fee
        if (adjustedFee < int256(MIN_FEE_BPS)) {
            adjustedFee = int256(MIN_FEE_BPS);
        } else if (adjustedFee > int256(MAX_FEE_BPS)) {
            adjustedFee = int256(MAX_FEE_BPS);
        }

        totalFeeBps = uint256(adjustedFee);

        // Split: 20% protocol, 80% LP
        protocolFeeBps = (totalFeeBps * 20) / 100;
        lpFeeBps = totalFeeBps - protocolFeeBps;

        return (totalFeeBps, protocolFeeBps, lpFeeBps);
    }

    /**
     * @notice Calculate fee amounts for a trade
     * @param tradeAmount Amount being traded
     * @param totalVolume Market volume
     * @param liquidity Market liquidity
     * @param marketAge Market age in seconds
     * @return totalFee Total fee amount
     * @return protocolFee Protocol fee amount
     * @return lpFee LP fee amount
     */
    function calculateFeeAmounts(
        uint256 tradeAmount,
        uint256 totalVolume,
        uint256 liquidity,
        uint256 marketAge
    )
        internal
        pure
        returns (uint256 totalFee, uint256 protocolFee, uint256 lpFee)
    {
        (
            uint256 totalFeeBps,
            uint256 protocolFeeBps,
            uint256 lpFeeBps
        ) = calculateDynamicFee(totalVolume, liquidity, marketAge);

        totalFee = (tradeAmount * totalFeeBps) / FEE_DENOMINATOR;
        protocolFee = (tradeAmount * protocolFeeBps) / FEE_DENOMINATOR;
        lpFee = (tradeAmount * lpFeeBps) / FEE_DENOMINATOR;

        return (totalFee, protocolFee, lpFee);
    }

    /**
     * @notice Calculate LP reward multiplier based on conditions
     * @param liquidityProvided Amount of liquidity provided
     * @param totalLiquidity Total liquidity in pool
     * @param timeStaked Time LP tokens have been staked
     * @return multiplier Reward multiplier in PRECISION units (1e18 = 1x)
     */
    function calculateLPRewardMultiplier(
        uint256 liquidityProvided,
        uint256 totalLiquidity,
        uint256 timeStaked
    ) internal pure returns (uint256 multiplier) {
        // Base multiplier = 1x
        multiplier = PRECISION;

        // Early LP bonus (first 20% of liquidity gets bonus)
        uint256 liquidityShare = (liquidityProvided * 100) / totalLiquidity;
        if (liquidityShare >= 20) {
            multiplier += PRECISION / 10; // +10% for large LPs
        }

        // Time-staked bonus
        if (timeStaked >= 90 days) {
            multiplier += PRECISION / 5; // +20% for 90+ days
        } else if (timeStaked >= 30 days) {
            multiplier += PRECISION / 10; // +10% for 30+ days
        } else if (timeStaked >= 7 days) {
            multiplier += PRECISION / 20; // +5% for 7+ days
        }

        // Cap at 2x
        if (multiplier > 2 * PRECISION) {
            multiplier = 2 * PRECISION;
        }

        return multiplier;
    }

    /**
     * @notice Get fee tier description
     * @param totalVolume Market volume
     * @param liquidity Market liquidity
     * @return tier Tier number (0 = base, 1 = reduced, 2 = premium)
     * @return description Tier description
     */
    function getFeeTier(
        uint256 totalVolume,
        uint256 liquidity
    ) internal pure returns (uint8 tier, string memory description) {
        if (
            totalVolume >= HIGH_VOLUME_THRESHOLD &&
            liquidity >= HIGH_LIQUIDITY_THRESHOLD
        ) {
            return (2, "Premium: Low fees, high liquidity");
        } else if (totalVolume >= MED_VOLUME_THRESHOLD) {
            return (1, "Standard: Medium fees");
        } else if (liquidity < LOW_LIQUIDITY_THRESHOLD) {
            return (0, "Risk: Higher fees, low liquidity");
        } else {
            return (1, "Standard: Base fees");
        }
    }
}
