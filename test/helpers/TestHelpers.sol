// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {wDAG} from "../../src/tokens/wDAG.sol";
import {FeeManager} from "../../src/fee/FeeManager.sol";
import {SocialPredictions} from "../../src/core/SocialPredictions.sol";
import {CategoricalMarket} from "../../src/core/CategoricalMarket.sol";
import {CategoricalMarketFactory} from "../../src/core/CategoricalMarketFactory.sol";
import {OutcomeToken} from "../../src/tokens/OutcomeToken.sol";
import {LPToken} from "../../src/tokens/LPToken.sol";

/**
 * @title TestHelpers
 * @notice Helper functions and utilities for testing
 */
contract TestHelpers is Test {
    // Constants
    uint256 internal constant INITIAL_BALANCE = 1_000_000 * 1e18; // 1M wDAG
    uint256 internal constant DEFAULT_LIQUIDITY = 10_000 * 1e18; // 10K wDAG
    uint256 internal constant DEFAULT_FEE_BPS = 30; // 0.3%

    // Core contracts
    wDAG internal collateral;
    FeeManager internal feeManager;
    SocialPredictions internal socialPredictions;
    CategoricalMarket internal marketImplementation;
    CategoricalMarketFactory internal factory;

    // Test accounts
    address internal owner;
    address internal treasury;
    address internal oracle;
    address internal admin;
    address internal alice;
    address internal bob;
    address internal carol;

    /**
     * @notice Set up core contracts and test accounts
     */
    function setupBase() internal {
        // Set up accounts
        owner = address(this);
        treasury = makeAddr("treasury");
        oracle = makeAddr("oracle");
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        // Deploy core contracts
        collateral = new wDAG();
        feeManager = new FeeManager(address(collateral), treasury);
        socialPredictions = new SocialPredictions();

        // Deploy implementation (note: needs actual token addresses, will be set by factory)
        marketImplementation = new CategoricalMarket(
            address(collateral),
            address(0), // Placeholder, set per market
            address(0), // Placeholder, set per market
            address(feeManager),
            address(socialPredictions)
        );

        factory = new CategoricalMarketFactory(
            address(marketImplementation),
            address(collateral),
            address(feeManager),
            address(socialPredictions),
            oracle,
            admin
        );

        // Transfer ownership
        factory.transferOwnership(owner);
        socialPredictions.transferOwnership(owner);
    }

    /**
     * @notice Fund a user with collateral tokens
     * @param user Address to fund
     * @param amount Amount of tokens to mint
     */
    function fundUser(address user, uint256 amount) internal {
        collateral.mint(user, amount);
    }

    /**
     * @notice Fund multiple users with default balance
     */
    function fundUsers() internal {
        fundUser(alice, INITIAL_BALANCE);
        fundUser(bob, INITIAL_BALANCE);
        fundUser(carol, INITIAL_BALANCE);
        fundUser(admin, INITIAL_BALANCE);
    }

    // ============================================
    // IPFS / UTILITY HELPERS
    // ============================================

    /**
     * @notice Helper to convert string to bytes32 (for IPFS CID simulation in tests)
     */
    function stringToBytes32(
        string memory source
    ) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }

    // ============================================
    // MARKET CREATION HELPERS
    // ============================================

    /**
     * @notice Create a simple binary market
     * @return market Address of created market
     */
    function createSimpleMarket() internal returns (address market) {
        // Simulate IPFS CID hash for market metadata
        bytes32 metadataURI = stringToBytes32("Will it rain tomorrow?");
        uint256 numOutcomes = 2;
        uint256 resolutionTime = block.timestamp + 7 days;

        vm.startPrank(admin);
        collateral.approve(address(factory), DEFAULT_LIQUIDITY);
        (market, , ) = factory.createMarket(
            metadataURI,
            numOutcomes,
            resolutionTime,
            DEFAULT_LIQUIDITY
        );
        vm.stopPrank();

        return market;
    }

    /**
     * @notice Create a market with custom parameters
     */
    function createCustomMarket(
        string memory question,
        uint256 numOutcomes,
        uint256 duration,
        uint256 initialLiquidity
    ) internal returns (address market) {
        // Convert question to bytes32 IPFS CID simulation
        bytes32 metadataURI = stringToBytes32(question);
        uint256 resolutionTime = block.timestamp + duration;

        vm.startPrank(admin);
        collateral.approve(address(factory), initialLiquidity);
        (market, , ) = factory.createMarket(
            metadataURI,
            numOutcomes,
            resolutionTime,
            initialLiquidity
        );
        vm.stopPrank();

        return market;
    }

    /**
     * @notice Create a 3-outcome categorical market
     */
    function createCategoricalMarket() internal returns (address market) {
        // Simulate IPFS CID hash for market metadata
        bytes32 metadataURI = stringToBytes32(
            "QmCategoricalMarketMetadataHash456"
        );
        uint256 numOutcomes = 3;
        uint256 resolutionTime = block.timestamp + 30 days;

        vm.startPrank(admin);
        collateral.approve(address(factory), DEFAULT_LIQUIDITY);
        (market, , ) = factory.createMarket(
            metadataURI,
            numOutcomes,
            resolutionTime,
            DEFAULT_LIQUIDITY
        );
        vm.stopPrank();

        return market;
    }

    /**
     * @notice Helper to buy shares for a user
     */
    function buySharesAs(
        address user,
        address market,
        uint8 outcome,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        collateral.approve(market, amount);
        CategoricalMarket(market).buyShares(outcome, 0, amount); // minShares=0, maxCost=amount
        vm.stopPrank();
    }

    /**
     * @notice Helper to sell shares for a user
     */
    function sellSharesAs(
        address user,
        address market,
        uint8 outcome,
        uint256 shares
    ) internal {
        vm.startPrank(user);
        CategoricalMarket(market).sellShares(outcome, shares, 0); // minPayout=0
        vm.stopPrank();
    }

    /**
     * @notice Helper to add liquidity as a user
     */
    function addLiquidityAs(
        address user,
        address market,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        collateral.approve(market, amount);
        CategoricalMarket(market).addLiquidity(amount);
        vm.stopPrank();
    }

    /**
     * @notice Helper to resolve market
     */
    function resolveMarket(address market, uint8 winningOutcome) internal {
        // Warp to resolution time
        (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
            market
        ).getMarketState();
        vm.warp(info.resolutionTime);

        vm.prank(oracle);
        CategoricalMarket(market).resolveMarket(winningOutcome);
    }

    /**
     * @notice Helper to claim winnings as a user
     */
    function claimWinningsAs(address user, address market) internal {
        vm.prank(user);
        CategoricalMarket(market).claimWinnings();
    }

    /**
     * @notice Get user's share balance for an outcome
     */
    function getUserShares(
        address market,
        address user,
        uint8 outcome
    ) internal view returns (uint256) {
        address outcomeToken = factory.getOutcomeToken(market);
        return OutcomeToken(outcomeToken).balanceOf(user, outcome);
    }

    /**
     * @notice Assert that two uints are approximately equal (within 1% tolerance)
     */
    function assertApproxEqRel(
        uint256 a,
        uint256 b,
        string memory err
    ) internal {
        uint256 percentDelta = 0.01e18; // 1%
        assertApproxEqRel(a, b, percentDelta, err);
    }

    /**
     * @notice Log market state for debugging
     */
    function logMarketState(address market) internal view {
        (
            CategoricalMarket.MarketInfo memory info,
            uint256[] memory prices,
            uint256[] memory quantities
        ) = CategoricalMarket(market).getMarketState();

        console.log("=== Market State ===");
        console.log("Metadata URI (bytes32):");
        console.logBytes32(info.metadataURI);
        console.log("Total Liquidity:", info.totalCollateral);
        console.log("Time to Resolution:", info.resolutionTime);

        for (uint256 i = 0; i < prices.length; i++) {
            console.log("Outcome", i);
            console.log("  Quantity:", quantities[i]);
            console.log("  Price:", prices[i]);
        }
    }

    /**
     * @notice Log user position for debugging
     */
    function logUserPosition(address market, address user) internal view {
        (
            uint256[] memory balances,
            uint256 currentValue,
            uint256 potentialWinnings
        ) = CategoricalMarket(market).getUserPosition(user);

        console.log("=== User Position ===");
        console.log("User:", user);
        console.log("Total Value:", currentValue);
        console.log("Potential Winnings:", potentialWinnings);

        for (uint256 i = 0; i < balances.length; i++) {
            console.log("Outcome", i, "shares:", balances[i]);
        }
    }

    /**
     * @notice Calculate expected shares for buying (for testing validation)
     */
    function calculateExpectedBuyShares(
        uint256 collateralAmount,
        uint256 feeBps
    ) internal pure returns (uint256 expectedShares, uint256 expectedFee) {
        expectedFee = (collateralAmount * feeBps) / 10000;
        expectedShares = collateralAmount - expectedFee;
        return (expectedShares, expectedFee);
    }
}
