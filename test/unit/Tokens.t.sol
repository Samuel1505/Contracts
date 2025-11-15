// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OutcomeToken} from "../../src/tokens/OutcomeToken.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";
import {wDAG} from "../../src/tokens/wDAG.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";

/**
 * @title TokensTest
 * @notice Tests for token contracts (OutcomeToken, LPToken, wDAG)
 */
contract TokensTest is TestHelpers {
    address market;
    OutcomeToken outcomeToken;
    LPToken lpToken;

    function setUp() public {
        setupBase();
        fundUsers();
        market = createSimpleMarket();
        outcomeToken = OutcomeToken(factory.getOutcomeToken(market));
        lpToken = LPToken(factory.getLPToken(market));
    }

    // ============================================
    // OUTCOME TOKEN TESTS
    // ============================================

    function test_OutcomeToken_OnlyMarketCanMint() public {
        vm.expectRevert(Errors.OnlyMarket.selector);
        outcomeToken.mint(alice, 0, 100 * 1e18);
    }

    function test_OutcomeToken_OnlyMarketCanBurn() public {
        // First mint via market
        vm.startPrank(alice);
        collateral.approve(market, 100 * 1e18);
        CategoricalMarket(market).mintCompleteSet(100 * 1e18);
        vm.stopPrank();

        // Try to burn directly
        vm.expectRevert(Errors.OnlyMarket.selector);
        outcomeToken.burn(alice, 0, 100 * 1e18);
    }

    function test_OutcomeToken_MintCompleteSet() public {
        uint256 amount = 100 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        CategoricalMarket(market).mintCompleteSet(amount);
        vm.stopPrank();

        // Check all outcomes have shares
        for (uint256 i = 0; i < 2; i++) {
            assertEq(
                outcomeToken.balanceOf(alice, i),
                amount,
                "Should have shares in all outcomes"
            );
        }
    }

    function test_OutcomeToken_BalanceOfAll() public {
        vm.startPrank(alice);
        collateral.approve(market, 100 * 1e18);
        CategoricalMarket(market).mintCompleteSet(100 * 1e18);
        vm.stopPrank();

        uint256[] memory balances = outcomeToken.balanceOfAll(alice);

        assertEq(balances.length, 2, "Should return balances for all outcomes");
        assertEq(balances[0], 100 * 1e18, "Should have correct balance for outcome 0");
        assertEq(balances[1], 100 * 1e18, "Should have correct balance for outcome 1");
    }

    function test_OutcomeToken_HasCompleteSet() public {
        vm.startPrank(alice);
        collateral.approve(market, 100 * 1e18);
        CategoricalMarket(market).mintCompleteSet(100 * 1e18);
        vm.stopPrank();

        (bool hasSet, uint256 numSets) = outcomeToken.hasCompleteSet(alice);

        assertTrue(hasSet, "Should have complete set");
        assertEq(numSets, 100 * 1e18, "Should have 100 complete sets");
    }

    function test_OutcomeToken_HasCompleteSet_Partial() public {
        // Buy shares of only one outcome
        vm.startPrank(alice);
        collateral.approve(market, 1000 * 1e18);
        CategoricalMarket(market).buyShares(0, 0, 1000 * 1e18);
        vm.stopPrank();

        (bool hasSet, uint256 numSets) = outcomeToken.hasCompleteSet(alice);

        assertFalse(hasSet, "Should not have complete set");
        assertEq(numSets, 0, "Should have zero complete sets");
    }

    function test_OutcomeToken_URI() public {
        string memory uri = outcomeToken.uri(0);

        assertGt(bytes(uri).length, 0, "URI should not be empty");
    }

    function test_OutcomeToken_URI_InvalidOutcome_Reverts() public {
        vm.expectRevert(Errors.InvalidOutcome.selector);
        outcomeToken.uri(10); // Only 2 outcomes (0, 1)
    }

    function test_OutcomeToken_NumOutcomes() public {
        assertEq(outcomeToken.numOutcomes(), 2, "Should have 2 outcomes");
    }

    function test_OutcomeToken_MetadataURI() public {
        bytes32 metadataURI = outcomeToken.metadataURI();
        assertNotEq(metadataURI, bytes32(0), "Should have metadata URI");
    }

    // ============================================
    // LP TOKEN TESTS
    // ============================================

    function test_LPToken_OnlyMarketCanMint() public {
        vm.expectRevert(Errors.OnlyMarket.selector);
        lpToken.mint(alice, 100 * 1e18);
    }

    function test_LPToken_OnlyMarketCanBurn() public {
        // First mint via market
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        uint256 balance = lpToken.balanceOf(alice);

        // Try to burn directly
        vm.expectRevert(Errors.OnlyMarket.selector);
        lpToken.burn(alice, balance);
    }

    function test_LPToken_MintOnAddLiquidity() public {
        uint256 amount = 10_000 * 1e18;

        vm.startPrank(alice);
        collateral.approve(market, amount);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(amount);
        vm.stopPrank();

        assertGt(lpTokens, 0, "Should receive LP tokens");
        assertEq(lpToken.balanceOf(alice), lpTokens, "Balance should match");
    }

    function test_LPToken_BurnOnRemoveLiquidity() public {
        // Add liquidity
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        uint256 balanceBefore = lpToken.balanceOf(alice);

        // Remove liquidity
        vm.startPrank(alice);
        CategoricalMarket(market).removeLiquidity(lpTokens);
        vm.stopPrank();

        assertEq(lpToken.balanceOf(alice), 0, "LP tokens should be burned");
    }

    function test_LPToken_Decimals() public {
        assertEq(lpToken.decimals(), 18, "Should have 18 decimals");
    }

    function test_LPToken_TotalSupply() public {
        uint256 supplyBefore = lpToken.totalSupply();

        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        uint256 supplyAfter = lpToken.totalSupply();

        assertGt(supplyAfter, supplyBefore, "Total supply should increase");
    }

    // ============================================
    // wDAG TOKEN TESTS
    // ============================================

    function test_wDAG_Mint() public {
        uint256 amount = 1000 * 1e18;
        uint256 balanceBefore = collateral.balanceOf(alice);

        collateral.mint(alice, amount);

        assertEq(collateral.balanceOf(alice), balanceBefore + amount, "Balance should increase");
    }

    function test_wDAG_Burn() public {
        uint256 amount = 1000 * 1e18;

        collateral.mint(alice, amount);
        uint256 balanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        collateral.burn(amount);

        assertEq(
            collateral.balanceOf(alice),
            balanceBefore - amount,
            "Balance should decrease"
        );
    }

    function test_wDAG_OnlyOwnerCanMint() public {
        vm.expectRevert();
        vm.prank(alice);
        collateral.mint(alice, 1000 * 1e18);
    }

    function test_wDAG_Decimals() public {
        assertEq(collateral.decimals(), 18, "Should have 18 decimals");
    }

    function test_wDAG_Name() public {
        assertEq(collateral.name(), "Wrapped DAG", "Should have correct name");
    }

    function test_wDAG_Symbol() public {
        assertEq(collateral.symbol(), "wDAG", "Should have correct symbol");
    }

    function test_wDAG_Transfer() public {
        uint256 amount = 1000 * 1e18;
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        uint256 bobBalanceBefore = collateral.balanceOf(bob);

        vm.prank(alice);
        collateral.transfer(bob, amount);

        assertEq(collateral.balanceOf(alice), aliceBalanceBefore - amount, "Alice balance should decrease");
        assertEq(collateral.balanceOf(bob), bobBalanceBefore + amount, "Bob balance should increase");
    }

    function test_wDAG_Approve() public {
        uint256 amount = 1000 * 1e18;
        collateral.mint(alice, amount);

        vm.prank(alice);
        collateral.approve(bob, amount);

        assertEq(collateral.allowance(alice, bob), amount, "Allowance should be set");
    }

    function test_wDAG_TransferFrom() public {
        uint256 amount = 1000 * 1e18;
        uint256 aliceBalanceBefore = collateral.balanceOf(alice);
        uint256 carolBalanceBefore = collateral.balanceOf(carol);

        vm.prank(alice);
        collateral.approve(bob, amount);

        vm.prank(bob);
        collateral.transferFrom(alice, carol, amount);

        assertEq(collateral.balanceOf(alice), aliceBalanceBefore - amount, "Alice balance should decrease");
        assertEq(collateral.balanceOf(carol), carolBalanceBefore + amount, "Carol balance should increase");
    }

    // ============================================
    // EDGE CASES
    // ============================================

    function test_OutcomeToken_MultipleMarkets() public {
        // Create second market
        address market2 = createSimpleMarket();
        OutcomeToken outcomeToken2 = OutcomeToken(factory.getOutcomeToken(market2));

        // Mint complete sets in both markets
        vm.startPrank(alice);
        collateral.approve(market, 100 * 1e18);
        CategoricalMarket(market).mintCompleteSet(100 * 1e18);

        collateral.approve(market2, 100 * 1e18);
        CategoricalMarket(market2).mintCompleteSet(100 * 1e18);
        vm.stopPrank();

        // Both markets should have balances
        assertEq(outcomeToken.balanceOf(alice, 0), 100 * 1e18, "Market 1 should have shares");
        assertEq(outcomeToken2.balanceOf(alice, 0), 100 * 1e18, "Market 2 should have shares");
    }

    function test_LPToken_Transfer() public {
        vm.startPrank(alice);
        collateral.approve(market, 10_000 * 1e18);
        uint256 lpTokens = CategoricalMarket(market).addLiquidity(10_000 * 1e18);
        vm.stopPrank();

        vm.prank(alice);
        lpToken.transfer(bob, lpTokens);

        assertEq(lpToken.balanceOf(alice), 0, "Alice should have no LP tokens");
        assertEq(lpToken.balanceOf(bob), lpTokens, "Bob should have LP tokens");
    }

    function test_OutcomeToken_BurnCompleteSet() public {
        vm.startPrank(alice);
        collateral.approve(market, 100 * 1e18);
        CategoricalMarket(market).mintCompleteSet(100 * 1e18);
        vm.stopPrank();

        // Burn via market
        vm.startPrank(alice);
        CategoricalMarket(market).burnCompleteSet(100 * 1e18);
        vm.stopPrank();

        // All balances should be zero
        for (uint256 i = 0; i < 2; i++) {
            assertEq(
                outcomeToken.balanceOf(alice, i),
                0,
                "All outcome balances should be zero"
            );
        }
    }
}

