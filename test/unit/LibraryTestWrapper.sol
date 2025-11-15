// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {LMSRMath} from "../../src/libraries/LMSRMath.sol";
import {CompleteSetLib} from "../../src/libraries/CompleteSetLib.sol";
import {Errors} from "../../src/utils/Errors.sol";

/**
 * @title LibraryTestWrapper
 * @notice Wrapper contract to test library function reverts
 */
contract LibraryTestWrapper {
    function testCalculateBuyCost(
        uint256[] memory quantities,
        uint8 outcomeIndex,
        uint256 shares,
        uint256 liquidityParameter
    ) external pure returns (uint256) {
        return LMSRMath.calculateBuyCost(quantities, outcomeIndex, shares, liquidityParameter);
    }

    function testCalculateSellPayout(
        uint256[] memory quantities,
        uint8 outcomeIndex,
        uint256 shares,
        uint256 liquidityParameter
    ) external pure returns (uint256) {
        return LMSRMath.calculateSellPayout(quantities, outcomeIndex, shares, liquidityParameter);
    }

    function testCalculateCostFunction(
        uint256[] memory quantities,
        uint256 b
    ) external pure returns (uint256) {
        return LMSRMath.calculateCostFunction(quantities, b);
    }

    function testCalculateLiquidityParameter(
        uint256 numOutcomes,
        uint256 initialLiquidity
    ) external pure returns (uint256) {
        return LMSRMath.calculateLiquidityParameter(numOutcomes, initialLiquidity);
    }

    function testCalculateMintCost(uint256 amount) external pure returns (uint256) {
        return CompleteSetLib.calculateMintCost(amount);
    }

    function testValidateCompleteSet(uint256[] memory balances) external pure returns (uint256) {
        return CompleteSetLib.validateCompleteSet(balances);
    }
}

