// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Errors} from "../utils/Errors.sol";

/**
 * @title LMSRMath
 * @notice Logarithmic Market Scoring Rule (LMSR) calculations for prediction markets
 * @dev Implements cost function: C(q) = b * log(sum(exp(q_i / b)))
 * where b is liquidity parameter, q_i is quantity of outcome i
 *
 * Price of outcome i: P_i = exp(q_i / b) / sum(exp(q_j / b))
 * Prices always sum to 1 (representing probabilities)
 */
library LMSRMath {
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_OUTCOMES = 10;

    // For fixed-point math approximations
    int256 private constant INT_PRECISION = 1e18;

    /**
     * @notice Calculate cost to buy shares using LMSR
     * @param quantities Current quantities of all outcomes
     * @param outcomeIndex Index of outcome to buy
     * @param shares Number of shares to buy
     * @param liquidityParameter Liquidity parameter (b)
     * @return cost Cost in collateral
     */
    function calculateBuyCost(
        uint256[] memory quantities,
        uint8 outcomeIndex,
        uint256 shares,
        uint256 liquidityParameter
    ) internal pure returns (uint256 cost) {
        if (outcomeIndex >= quantities.length) revert Errors.InvalidOutcome();
        if (shares == 0) revert Errors.ZeroAmount();

        // Cost = C(q + Δq) - C(q)
        uint256 costBefore = calculateCostFunction(
            quantities,
            liquidityParameter
        );

        // Update quantities
        uint256[] memory newQuantities = new uint256[](quantities.length);
        for (uint256 i = 0; i < quantities.length; i++) {
            if (i == outcomeIndex) {
                newQuantities[i] = quantities[i] + shares;
            } else {
                newQuantities[i] = quantities[i];
            }
        }

        uint256 costAfter = calculateCostFunction(
            newQuantities,
            liquidityParameter
        );

        cost = costAfter - costBefore;
        return cost;
    }

    /**
     * @notice Calculate payout for selling shares using LMSR
     * @param quantities Current quantities of all outcomes
     * @param outcomeIndex Index of outcome to sell
     * @param shares Number of shares to sell
     * @param liquidityParameter Liquidity parameter (b)
     * @return payout Payout in collateral
     */
    function calculateSellPayout(
        uint256[] memory quantities,
        uint8 outcomeIndex,
        uint256 shares,
        uint256 liquidityParameter
    ) internal pure returns (uint256 payout) {
        if (outcomeIndex >= quantities.length) revert Errors.InvalidOutcome();
        if (shares == 0) revert Errors.ZeroAmount();
        if (shares > quantities[outcomeIndex])
            revert Errors.InsufficientShares();

        // Payout = C(q) - C(q - Δq)
        uint256 costBefore = calculateCostFunction(
            quantities,
            liquidityParameter
        );

        // Update quantities
        uint256[] memory newQuantities = new uint256[](quantities.length);
        for (uint256 i = 0; i < quantities.length; i++) {
            if (i == outcomeIndex) {
                newQuantities[i] = quantities[i] - shares;
            } else {
                newQuantities[i] = quantities[i];
            }
        }

        uint256 costAfter = calculateCostFunction(
            newQuantities,
            liquidityParameter
        );

        payout = costBefore - costAfter;
        return payout;
    }

    /**
     * @notice Calculate LMSR cost function: C(q) = b * log(sum(exp(q_i / b)))
     * @param quantities Quantities of all outcomes
     * @param b Liquidity parameter
     * @return cost Cost function value
     */
    function calculateCostFunction(
        uint256[] memory quantities,
        uint256 b
    ) internal pure returns (uint256 cost) {
        if (b == 0) revert Errors.InvalidParameter();

        // For numerical stability, use: log(sum(exp(x_i))) = max(x) + log(sum(exp(x_i - max(x))))
        uint256 maxQuantity = 0;
        for (uint256 i = 0; i < quantities.length; i++) {
            if (quantities[i] > maxQuantity) {
                maxQuantity = quantities[i];
            }
        }

        // Calculate sum(exp((q_i - max) / b))
        uint256 sumExp = 0;
        for (uint256 i = 0; i < quantities.length; i++) {
            int256 exponent = int256((quantities[i] * PRECISION) / b) -
                int256((maxQuantity * PRECISION) / b);
            sumExp += uint256(exp(exponent));
        }

        // C(q) = b * (max/b + log(sumExp))
        cost = maxQuantity + (b * ln(sumExp)) / PRECISION;

        return cost;
    }

    /**
     * @notice Calculate current prices for all outcomes
     * @param quantities Current quantities
     * @param liquidityParameter Liquidity parameter
     * @return prices Array of prices (sum to PRECISION = 1e18 = 100%)
     */
    function calculatePrices(
        uint256[] memory quantities,
        uint256 liquidityParameter
    ) internal pure returns (uint256[] memory prices) {
        prices = new uint256[](quantities.length);

        // Price_i = exp(q_i / b) / sum(exp(q_j / b))

        // For numerical stability
        uint256 maxQuantity = 0;
        for (uint256 i = 0; i < quantities.length; i++) {
            if (quantities[i] > maxQuantity) {
                maxQuantity = quantities[i];
            }
        }

        // Calculate exp((q_i - max) / b) for each outcome
        uint256[] memory expValues = new uint256[](quantities.length);
        uint256 sumExp = 0;

        for (uint256 i = 0; i < quantities.length; i++) {
            int256 exponent = int256(
                (quantities[i] * PRECISION) / liquidityParameter
            ) - int256((maxQuantity * PRECISION) / liquidityParameter);
            expValues[i] = uint256(exp(exponent));
            sumExp += expValues[i];
        }

        // Calculate normalized prices
        for (uint256 i = 0; i < quantities.length; i++) {
            prices[i] = (expValues[i] * PRECISION) / sumExp;
        }

        return prices;
    }

    /**
     * @notice Calculate optimal liquidity parameter based on initial liquidity
     * @param numOutcomes Number of outcomes
     * @param initialLiquidity Initial liquidity amount
     * @return b Optimal liquidity parameter
     */
    function calculateLiquidityParameter(
        uint256 numOutcomes,
        uint256 initialLiquidity
    ) internal pure returns (uint256 b) {
        if (numOutcomes == 0 || numOutcomes > MAX_OUTCOMES)
            revert Errors.InvalidOutcomeCount();
        if (initialLiquidity == 0) revert Errors.ZeroAmount();

        // b ≈ initialLiquidity / ln(numOutcomes)
        // This ensures equal initial prices and proper market depth
        uint256 lnOutcomes = ln(numOutcomes * PRECISION);
        b = (initialLiquidity * PRECISION) / lnOutcomes;

        return b;
    }

    /**
     * @notice Approximate natural logarithm using Taylor series
     * @dev ln(x) for x in range (0.5, 2) using Taylor series around 1
     * For x outside range, use: ln(x) = ln(x/2^n) + n*ln(2)
     * @param x Input value (in PRECISION units)
     * @return result ln(x) (in PRECISION units)
     */
    function ln(uint256 x) internal pure returns (uint256) {
        if (x == 0) revert Errors.InvalidParameter();
        if (x == PRECISION) return 0; // ln(1) = 0

        // Scale x to range [0.5, 2)
        int256 powerAdjust = 0;
        uint256 scaledX = x;

        while (scaledX >= 2 * PRECISION) {
            scaledX = scaledX / 2;
            powerAdjust++;
        }

        while (scaledX < PRECISION / 2) {
            scaledX = scaledX * 2;
            powerAdjust--;
        }

        // Taylor series: ln(x) = (x-1) - (x-1)²/2 + (x-1)³/3 - ...
        int256 y = int256(scaledX) - int256(PRECISION);
        int256 result = 0;
        int256 term = y;

        // First 10 terms for accuracy
        for (uint256 i = 1; i <= 10; i++) {
            if (i > 1) {
                term = (term * y) / int256(PRECISION);
            }

            if (i % 2 == 1) {
                result += term / int256(i);
            } else {
                result -= term / int256(i);
            }
        }

        // Add back the scaling factor: n * ln(2)
        // ln(2) ≈ 0.693147180559945309 in PRECISION
        int256 ln2 = 693147180559945309;
        result += powerAdjust * ln2;

        return uint256(result);
    }

    /**
     * @notice Approximate exponential function e^x using Taylor series
     * @dev exp(x) = 1 + x + x²/2! + x³/3! + ...
     * For large x, use: e^x = e^(integer_part) * e^(fractional_part)
     * @param x Input value (in PRECISION units, can be negative)
     * @return result e^x (in PRECISION units)
     */
    function exp(int256 x) internal pure returns (int256) {
        if (x == 0) return int256(PRECISION); // e^0 = 1

        bool negative = x < 0;
        uint256 absX = negative ? uint256(-x) : uint256(x);

        // For numerical stability, limit input range
        if (absX > 20 * uint256(PRECISION)) {
            // e^20 ≈ 485,165,195 - very large
            // Return max value or very small value
            return negative ? int256(1) : int256(485165195 * PRECISION);
        }

        // Separate integer and fractional parts
        uint256 integerPart = absX / uint256(PRECISION);
        uint256 fractionalPart = absX % uint256(PRECISION);

        // Calculate e^(fractional_part) using Taylor series
        uint256 result = PRECISION;
        uint256 term = fractionalPart;

        // First 15 terms for accuracy
        for (uint256 i = 1; i <= 15; i++) {
            result += term;
            term = (term * fractionalPart) / (uint256(PRECISION) * (i + 1));

            if (term < 1) break; // Convergence
        }

        // Multiply by e^integer_part
        // e ≈ 2.718281828459045235
        uint256 e = 2718281828459045235;
        for (uint256 i = 0; i < integerPart; i++) {
            result = (result * e) / PRECISION;
        }

        if (negative) {
            // e^(-x) = 1 / e^x
            return int256((PRECISION * PRECISION) / result);
        }

        return int256(result);
    }

    /**
     * @notice Calculate price impact for a trade
     * @param quantities Current quantities
     * @param outcomeIndex Outcome to trade
     * @param shares Shares to trade (positive for buy, negative for sell)
     * @param liquidityParameter Liquidity parameter
     * @return priceImpact Price impact in basis points
     */
    function calculatePriceImpact(
        uint256[] memory quantities,
        uint8 outcomeIndex,
        int256 shares,
        uint256 liquidityParameter
    ) internal pure returns (uint256 priceImpact) {
        uint256[] memory pricesBefore = calculatePrices(
            quantities,
            liquidityParameter
        );

        // Simulate trade
        uint256[] memory newQuantities = new uint256[](quantities.length);
        for (uint256 i = 0; i < quantities.length; i++) {
            if (i == outcomeIndex) {
                if (shares > 0) {
                    newQuantities[i] = quantities[i] + uint256(shares);
                } else {
                    newQuantities[i] = quantities[i] - uint256(-shares);
                }
            } else {
                newQuantities[i] = quantities[i];
            }
        }

        uint256[] memory pricesAfter = calculatePrices(
            newQuantities,
            liquidityParameter
        );

        // Calculate impact in basis points
        uint256 priceDiff = pricesAfter[outcomeIndex] >
            pricesBefore[outcomeIndex]
            ? pricesAfter[outcomeIndex] - pricesBefore[outcomeIndex]
            : pricesBefore[outcomeIndex] - pricesAfter[outcomeIndex];

        priceImpact = (priceDiff * 10000) / pricesBefore[outcomeIndex];

        return priceImpact;
    }
}
