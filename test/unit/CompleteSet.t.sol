// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompleteSetLib} from "../../src/libraries/CompleteSetLib.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {LibraryTestWrapper} from "./LibraryTestWrapper.sol";

/**
 * @title CompleteSetTest
 * @notice Tests for complete set mechanics
 */
contract CompleteSetTest is TestHelpers {
    LibraryTestWrapper wrapper;

    function setUp() public {
        setupBase();
        wrapper = new LibraryTestWrapper();
    }

    // ============================================
    // MINT COST TESTS
    // ============================================

    function test_CalculateMintCost_OneToOne() public {
        uint256 amount = 100 * 1e18;
        uint256 cost = CompleteSetLib.calculateMintCost(amount);

        assertEq(cost, amount, "Mint cost should be 1:1");
    }

    function test_CalculateMintCost_Zero_Reverts() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        wrapper.testCalculateMintCost(0);
    }

    function test_CalculateMintCost_LargeAmount() public {
        uint256 amount = 1_000_000 * 1e18;
        uint256 cost = CompleteSetLib.calculateMintCost(amount);

        assertEq(cost, amount, "Mint cost should be 1:1 even for large amounts");
    }

    // ============================================
    // BURN PAYOUT TESTS
    // ============================================

    function test_CalculateBurnPayout_OneToOne() public {
        uint256 amount = 100 * 1e18;
        uint256 payout = CompleteSetLib.calculateBurnPayout(amount);

        assertEq(payout, amount, "Burn payout should be 1:1");
    }

    function test_CalculateBurnPayout_Zero_ReturnsZero() public {
        uint256 payout = CompleteSetLib.calculateBurnPayout(0);
        assertEq(payout, 0, "Burn payout should return zero for zero amount");
    }

    // ============================================
    // VALIDATION TESTS
    // ============================================

    function test_HasCompleteSet_Valid() public {
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100 * 1e18;
        balances[1] = 100 * 1e18;
        balances[2] = 100 * 1e18;

        bool hasSet = CompleteSetLib.hasCompleteSet(balances, 100 * 1e18);
        assertTrue(hasSet, "Should have complete set");
    }

    function test_HasCompleteSet_Insufficient() public {
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100 * 1e18;
        balances[1] = 100 * 1e18;
        balances[2] = 50 * 1e18; // Less than needed

        bool hasSet = CompleteSetLib.hasCompleteSet(balances, 100 * 1e18);
        assertFalse(hasSet, "Should not have enough for complete set");
    }

    function test_HasCompleteSet_Partial() public {
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100 * 1e18;
        balances[1] = 100 * 1e18;
        balances[2] = 100 * 1e18;

        bool hasSet = CompleteSetLib.hasCompleteSet(balances, 50 * 1e18);
        assertTrue(hasSet, "Should have enough for partial complete set");
    }

    function test_ValidateCompleteSet_ReturnsMinimum() public {
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100 * 1e18;
        balances[1] = 150 * 1e18;
        balances[2] = 200 * 1e18;

        uint256 numSets = CompleteSetLib.validateCompleteSet(balances);

        assertEq(numSets, 100 * 1e18, "Should return minimum balance");
    }

    function test_ValidateCompleteSet_ZeroBalances() public {
        uint256[] memory balances = new uint256[](3);
        balances[0] = 0;
        balances[1] = 0;
        balances[2] = 0;

        uint256 numSets = CompleteSetLib.validateCompleteSet(balances);

        assertEq(numSets, 0, "Should return zero for zero balances");
    }

    function test_ValidateCompleteSet_EmptyArray_Reverts() public {
        uint256[] memory balances = new uint256[](0);

        vm.expectRevert(Errors.InvalidOutcomeCount.selector);
        wrapper.testValidateCompleteSet(balances);
    }

    // ============================================
    // ARBITRAGE TESTS
    // ============================================

    function test_CheckArbitrage_NoArbitrage() public {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0.33e18;
        prices[1] = 0.33e18;
        prices[2] = 0.34e18;

        (bool hasArbitrage, uint256 costDifference) = CompleteSetLib.checkArbitrage(prices);

        // Prices sum to approximately 1, so minimal arbitrage
        assertTrue(!hasArbitrage || costDifference < 0.01e18, "Should have minimal or no arbitrage");
    }

    function test_CheckArbitrage_PricesSumToOne() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0.5e18;
        prices[1] = 0.5e18;

        (bool hasArbitrage, uint256 costDifference) = CompleteSetLib.checkArbitrage(prices);

        assertFalse(hasArbitrage, "Prices summing to 1 should have no arbitrage");
        assertEq(costDifference, 0, "Cost difference should be zero");
    }

    function test_CheckArbitrage_PricesSumGreaterThanOne() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0.6e18;
        prices[1] = 0.6e18; // Sum = 1.2

        (bool hasArbitrage, uint256 costDifference) = CompleteSetLib.checkArbitrage(prices);

        assertTrue(hasArbitrage, "Prices > 1 should indicate arbitrage");
        assertGt(costDifference, 0, "Should have positive cost difference");
    }

    function test_CheckArbitrage_PricesSumLessThanOne() public {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 0.3e18;
        prices[1] = 0.3e18; // Sum = 0.6

        (bool hasArbitrage, uint256 costDifference) = CompleteSetLib.checkArbitrage(prices);

        assertTrue(hasArbitrage, "Prices < 1 should indicate arbitrage");
        assertGt(costDifference, 0, "Should have positive cost difference");
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_HasCompleteSet_OneOutcome() public {
        uint256[] memory balances = new uint256[](1);
        balances[0] = 100 * 1e18;

        bool hasSet = CompleteSetLib.hasCompleteSet(balances, 100 * 1e18);
        assertTrue(hasSet, "Single outcome should work");
    }

    function test_HasCompleteSet_TenOutcomes() public {
        uint256[] memory balances = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            balances[i] = 100 * 1e18;
        }

        bool hasSet = CompleteSetLib.hasCompleteSet(balances, 100 * 1e18);
        assertTrue(hasSet, "Ten outcomes should work");
    }

    function test_ValidateCompleteSet_UnevenBalances() public {
        uint256[] memory balances = new uint256[](4);
        balances[0] = 1000 * 1e18;
        balances[1] = 500 * 1e18;
        balances[2] = 750 * 1e18;
        balances[3] = 300 * 1e18;

        uint256 numSets = CompleteSetLib.validateCompleteSet(balances);

        assertEq(numSets, 300 * 1e18, "Should return minimum balance");
    }
}

