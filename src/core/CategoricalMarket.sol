// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LMSRMath} from "../libraries/LMSRMath.sol";
import {CompleteSetLib} from "../libraries/CompleteSetLib.sol";
import {OutcomeToken} from "../tokens/OutcomeToken.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {FeeManager} from "../fee/FeeManager.sol";
import {SocialPredictions} from "./SocialPredictions.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title CategoricalMarket
 * @notice LMSR-based categorical prediction market with complete sets and social features
 * @dev This is a production-ready implementation with:
 * - LMSR pricing (prices sum to 1)
 * - Complete set mechanics
 * - Dynamic fees with LP rewards
 * - Social predictions integration
 * - Gas-optimized with ERC1155 outcome tokens
 */
contract CategoricalMarket is ReentrancyGuard {
    enum MarketStatus {
        ACTIVE,
        RESOLVED,
        CANCELLED
    }

    struct MarketInfo {
        bytes32 metadataURI; // IPFS CID containing question, description, images
        uint256 liquidityParameter;
        uint256 totalCollateral;
        uint256 liquidityPool;
        uint256 resolutionTime;
        uint256 createdAt;
        MarketStatus status;
        uint8 winningOutcome;
        address oracleResolver;
        uint256 totalVolume;
    }

    // Core state
    MarketInfo public market;
    uint256[] public outcomeQuantities; // q_i for LMSR

    // Contract references
    IERC20 public immutable collateralToken;
    OutcomeToken public outcomeToken; // Changed from immutable to allow per-clone values
    LPToken public lpToken; // Changed from immutable to allow per-clone values
    FeeManager public immutable feeManager;
    SocialPredictions public immutable socialPredictions;

    // Claim tracking
    mapping(address => bool) public hasClaimed;
    bool private initialized;

    // Modifiers
    modifier onlyOracle() {
        if (msg.sender != market.oracleResolver) revert Errors.OnlyOracle();
        _;
    }

    modifier onlyActive() {
        if (market.status != MarketStatus.ACTIVE)
            revert Errors.MarketNotActive();
        _;
    }

    modifier onlyResolved() {
        if (market.status != MarketStatus.RESOLVED)
            revert Errors.MarketNotResolved();
        _;
    }

    modifier onlyInitialized() {
        if (!initialized) revert Errors.NotInitialized();
        _;
    }

    /**
     * @notice Constructor (called by factory via minimal proxy)
     * @param _collateralToken Collateral token (wDAG)
     * @param _outcomeToken Outcome token (ERC1155)
     * @param _lpToken LP token
     * @param _feeManager Fee manager
     * @param _socialPredictions Social predictions contract
     */
    constructor(
        address _collateralToken,
        address _outcomeToken,
        address _lpToken,
        address _feeManager,
        address _socialPredictions
    ) {
        collateralToken = IERC20(_collateralToken);
        outcomeToken = OutcomeToken(_outcomeToken);
        lpToken = LPToken(_lpToken);
        feeManager = FeeManager(_feeManager);
        socialPredictions = SocialPredictions(_socialPredictions);
    }

    /**
     * @notice Initialize market (called by factory after deployment)
     * @param metadataURI IPFS CID containing market metadata (question, description, images)
     * @param numOutcomes Number of outcomes
     * @param resolutionTime When market can be resolved
     * @param oracleResolver Oracle address
     * @param initialLiquidity Initial liquidity amount
     * @param _outcomeToken Outcome token address (set by factory)
     * @param _lpToken LP token address (set by factory)
     */
    function initialize(
        bytes32 metadataURI,
        uint256 numOutcomes,
        uint256 resolutionTime,
        address oracleResolver,
        uint256 initialLiquidity,
        address _outcomeToken,
        address _lpToken
    ) external {
        if (initialized) revert Errors.AlreadyInitialized();
        if (metadataURI == bytes32(0)) revert Errors.InvalidParameter();
        if (numOutcomes < 2 || numOutcomes > 10)
            revert Errors.InvalidOutcomeCount();
        if (resolutionTime <= block.timestamp)
            revert Errors.ResolutionTimePassed();
        if (oracleResolver == address(0)) revert Errors.InvalidAddress();
        if (initialLiquidity == 0) revert Errors.ZeroAmount();
        if (_outcomeToken == address(0) || _lpToken == address(0))
            revert Errors.InvalidAddress();

        initialized = true;
        
        // Set token addresses (from factory)
        outcomeToken = OutcomeToken(_outcomeToken);
        lpToken = LPToken(_lpToken);

        // Calculate optimal liquidity parameter
        uint256 b = LMSRMath.calculateLiquidityParameter(
            numOutcomes,
            initialLiquidity
        );

        market = MarketInfo({
            metadataURI: metadataURI,
            liquidityParameter: b,
            totalCollateral: 0,
            liquidityPool: 0,
            resolutionTime: resolutionTime,
            createdAt: block.timestamp,
            status: MarketStatus.ACTIVE,
            winningOutcome: 0,
            oracleResolver: oracleResolver,
            totalVolume: 0
        });

        // Initialize outcome quantities to 0 (equal prices)
        for (uint256 i = 0; i < numOutcomes; i++) {
            outcomeQuantities.push(0);
        }

        emit Events.MarketInitialized(
            metadataURI,
            numOutcomes,
            resolutionTime,
            oracleResolver
        );
    }

    // ============================================
    // COMPLETE SET OPERATIONS
    // ============================================

    /**
     * @notice Mint complete set (1 collateral → 1 share of each outcome)
     * @param amount Number of complete sets to mint
     */
    function mintCompleteSet(
        uint256 amount
    ) external onlyActive onlyInitialized nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 cost = CompleteSetLib.calculateMintCost(amount);

        // Transfer collateral from user
        bool success = collateralToken.transferFrom(
            msg.sender,
            address(this),
            cost
        );
        if (!success) revert Errors.InsufficientCollateral();

        // Mint outcome tokens to user
        outcomeToken.mintCompleteSet(msg.sender, amount);

        // Update collateral tracking
        market.totalCollateral += cost;

        emit Events.SharesPurchased(msg.sender, 255, amount, cost); // 255 = complete set indicator
    }

    /**
     * @notice Burn complete set (1 share of each outcome → 1 collateral)
     * @param amount Number of complete sets to burn
     */
    function burnCompleteSet(
        uint256 amount
    ) external onlyActive onlyInitialized nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();

        // Check user has complete sets
        uint256[] memory balances = outcomeToken.balanceOfAll(msg.sender);
        if (!CompleteSetLib.hasCompleteSet(balances, amount)) {
            revert Errors.InsufficientShares();
        }

        uint256 payout = CompleteSetLib.calculateBurnPayout(amount);

        // Burn outcome tokens from user
        outcomeToken.burnCompleteSet(msg.sender, amount);

        // Update collateral tracking
        market.totalCollateral -= payout;

        // Transfer collateral to user
        bool success = collateralToken.transfer(msg.sender, payout);
        if (!success) revert Errors.InsufficientCollateral();

        emit Events.SharesSold(msg.sender, 255, amount, payout); // 255 = complete set indicator
    }

    // ============================================
    // LMSR TRADING
    // ============================================

    /**
     * @notice Buy shares for a specific outcome using LMSR
     * @param outcomeIndex Outcome to buy
     * @param minShares Minimum shares to receive (slippage protection)
     * @param maxCost Maximum cost willing to pay
     * @return shares Shares received
     * @return cost Total cost paid
     */
    function buyShares(
        uint8 outcomeIndex,
        uint256 minShares,
        uint256 maxCost
    )
        external
        onlyActive
        onlyInitialized
        nonReentrant
        returns (uint256 shares, uint256 cost)
    {
        if (outcomeIndex >= outcomeQuantities.length)
            revert Errors.InvalidOutcome();

        // For buying, we need to determine shares from maxCost
        // Binary search to find optimal shares for given maxCost
        shares = _calculateSharesForCost(outcomeIndex, maxCost);

        if (shares < minShares) revert Errors.SlippageExceeded();

        // Calculate actual cost using LMSR
        uint256 baseCost = LMSRMath.calculateBuyCost(
            outcomeQuantities,
            outcomeIndex,
            shares,
            market.liquidityParameter
        );

        // Approve FeeManager for fees (approve maxCost to cover fees)
        collateralToken.approve(address(feeManager), maxCost);

        // Collect fees
        (uint256 protocolFee, uint256 lpFee) = feeManager.collectTradeFees(
            address(this),
            baseCost
        );

        cost = baseCost + protocolFee + lpFee;

        if (cost > maxCost) revert Errors.SlippageExceeded();

        // Transfer collateral from user (including fees)
        bool success = collateralToken.transferFrom(
            msg.sender,
            address(this),
            cost
        );
        if (!success) revert Errors.InsufficientCollateral();

        // Update LMSR state
        outcomeQuantities[outcomeIndex] += shares;
        market.totalCollateral += baseCost;
        market.totalVolume += baseCost;

        // Mint outcome tokens to user
        outcomeToken.mint(msg.sender, outcomeIndex, shares);

        emit Events.SharesPurchased(msg.sender, outcomeIndex, shares, cost);

        return (shares, cost);
    }

    /**
     * @notice Sell shares for a specific outcome using LMSR
     * @param outcomeIndex Outcome to sell
     * @param sharesToSell Number of shares to sell
     * @param minPayout Minimum payout expected (slippage protection)
     * @return payout Amount received
     */
    function sellShares(
        uint8 outcomeIndex,
        uint256 sharesToSell,
        uint256 minPayout
    )
        external
        onlyActive
        onlyInitialized
        nonReentrant
        returns (uint256 payout)
    {
        if (outcomeIndex >= outcomeQuantities.length)
            revert Errors.InvalidOutcome();
        if (sharesToSell == 0) revert Errors.ZeroAmount();
        if (outcomeToken.balanceOf(msg.sender, outcomeIndex) < sharesToSell) {
            revert Errors.InsufficientShares();
        }

        // Calculate payout using LMSR
        uint256 basePayout = LMSRMath.calculateSellPayout(
            outcomeQuantities,
            outcomeIndex,
            sharesToSell,
            market.liquidityParameter
        );

        // Approve FeeManager for fees
        collateralToken.approve(address(feeManager), basePayout);

        // Collect fees
        (uint256 protocolFee, uint256 lpFee) = feeManager.collectTradeFees(
            address(this),
            basePayout
        );

        payout = basePayout - protocolFee - lpFee;

        if (payout < minPayout) revert Errors.SlippageExceeded();

        // Update LMSR state
        outcomeQuantities[outcomeIndex] -= sharesToSell;
        market.totalCollateral -= basePayout;
        market.totalVolume += basePayout;

        // Burn outcome tokens from user
        outcomeToken.burn(msg.sender, outcomeIndex, sharesToSell);

        // Note: Fees are already transferred by collectTradeFees

        // Transfer payout to user
        bool success = collateralToken.transfer(msg.sender, payout);
        if (!success) revert Errors.InsufficientCollateral();

        emit Events.SharesSold(msg.sender, outcomeIndex, sharesToSell, payout);

        return payout;
    }

    // ============================================
    // LIQUIDITY PROVISION
    // ============================================

    /**
     * @notice Add liquidity to the market
     * @param amount Amount of collateral to add
     * @return lpTokensAmount LP tokens minted
     */
    function addLiquidity(
        uint256 amount
    )
        external
        onlyActive
        onlyInitialized
        nonReentrant
        returns (uint256 lpTokensAmount)
    {
        if (amount == 0) revert Errors.ZeroAmount();

        // Calculate LP tokens to mint (proportional to current pool)
        uint256 currentSupply = lpToken.totalSupply();

        if (currentSupply == 0) {
            lpTokensAmount = amount; // First LP gets 1:1
        } else {
            lpTokensAmount = (amount * currentSupply) / market.liquidityPool;
        }

        // Transfer collateral from user
        bool success = collateralToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert Errors.InsufficientCollateral();

        // Update state
        market.liquidityPool += amount;
        market.totalCollateral += amount;

        // Increase liquidity parameter to maintain market depth
        // For first liquidity, don't adjust (already set correctly in initialize)
        if (market.liquidityPool > amount) {
            market.liquidityParameter =
                (market.liquidityParameter * market.liquidityPool) /
                (market.liquidityPool - amount);
        }

        // Mint LP tokens
        lpToken.mint(msg.sender, lpTokensAmount);

        // Register with fee manager
        feeManager.registerLP(
            address(this),
            msg.sender,
            amount,
            lpTokensAmount
        );

        emit Events.LiquidityAdded(msg.sender, amount, lpTokensAmount);

        return lpTokensAmount;
    }

    /**
     * @notice Remove liquidity from the market
     * @param lpTokensAmount Amount of LP tokens to burn
     * @return collateralAmount Collateral returned
     */
    function removeLiquidity(
        uint256 lpTokensAmount
    )
        external
        onlyActive
        onlyInitialized
        nonReentrant
        returns (uint256 collateralAmount)
    {
        if (lpTokensAmount == 0) revert Errors.ZeroAmount();
        if (lpToken.balanceOf(msg.sender) < lpTokensAmount)
            revert Errors.NoLPTokens();

        uint256 totalSupply = lpToken.totalSupply();

        // Calculate collateral to return
        collateralAmount =
            (lpTokensAmount * market.liquidityPool) /
            totalSupply;

        // Ensure we don't remove more than available
        if (collateralAmount > market.liquidityPool) {
            collateralAmount = market.liquidityPool;
        }

        // Update state
        market.liquidityPool -= collateralAmount;
        market.totalCollateral -= collateralAmount;

        // Adjust liquidity parameter (only if not removing all liquidity)
        uint256 newPool = market.liquidityPool;
        if (newPool > 0 && collateralAmount > 0) {
            market.liquidityParameter =
                (market.liquidityParameter * newPool) /
                (newPool + collateralAmount);
        }

        // Burn LP tokens
        lpToken.burn(msg.sender, lpTokensAmount);

        // Unregister with fee manager
        feeManager.unregisterLP(address(this), msg.sender, lpTokensAmount);

        // Transfer collateral
        bool success = collateralToken.transfer(msg.sender, collateralAmount);
        if (!success) revert Errors.InsufficientCollateral();

        emit Events.LiquidityRemoved(
            msg.sender,
            lpTokensAmount,
            collateralAmount
        );

        return collateralAmount;
    }

    // ============================================
    // RESOLUTION & CLAIMS
    // ============================================

    /**
     * @notice Resolve market with winning outcome
     * @param winningOutcomeIndex Index of winning outcome
     */
    function resolveMarket(
        uint8 winningOutcomeIndex
    ) external onlyOracle onlyActive onlyInitialized {
        if (block.timestamp < market.resolutionTime) {
            revert Errors.ResolutionTimeNotReached();
        }
        if (winningOutcomeIndex >= outcomeQuantities.length) {
            revert Errors.InvalidOutcome();
        }

        market.status = MarketStatus.RESOLVED;
        market.winningOutcome = winningOutcomeIndex;

        emit Events.MarketResolved(winningOutcomeIndex, block.timestamp);
    }

    /**
     * @notice Claim winnings after resolution
     * @return winnings Amount claimed
     */
    function claimWinnings()
        external
        onlyResolved
        onlyInitialized
        nonReentrant
        returns (uint256 winnings)
    {
        if (hasClaimed[msg.sender]) revert Errors.AlreadyClaimed();

        uint256 winningShares = outcomeToken.balanceOf(
            msg.sender,
            market.winningOutcome
        );
        if (winningShares == 0) revert Errors.NothingToClaim();

        hasClaimed[msg.sender] = true;
        winnings = winningShares; // 1:1 payout

        // Burn winning shares
        outcomeToken.burn(msg.sender, market.winningOutcome, winningShares);

        // Transfer winnings
        bool success = collateralToken.transfer(msg.sender, winnings);
        if (!success) revert Errors.InsufficientCollateral();

        emit Events.WinningsClaimed(msg.sender, winnings);

        return winnings;
    }

    // ============================================
    // VIEW FUNCTIONS - RICH GETTERS
    // ============================================

    /**
     * @notice Get current prices for all outcomes (using LMSR)
     * @return prices Array of prices (sum to 1e18 = 100%)
     */
    function getOutcomePrices()
        external
        view
        returns (uint256[] memory prices)
    {
        return
            LMSRMath.calculatePrices(
                outcomeQuantities,
                market.liquidityParameter
            );
    }

    /**
     * @notice Simulate buy order
     * @param outcomeIndex Outcome to buy
     * @param cost Amount of collateral to spend
     * @return shares Shares that would be received
     * @return totalCost Total cost including fees
     * @return priceImpact Price impact in basis points
     */
    function simulateBuy(
        uint8 outcomeIndex,
        uint256 cost
    )
        external
        view
        returns (uint256 shares, uint256 totalCost, uint256 priceImpact)
    {
        shares = _calculateSharesForCost(outcomeIndex, cost);

        uint256 baseCost = LMSRMath.calculateBuyCost(
            outcomeQuantities,
            outcomeIndex,
            shares,
            market.liquidityParameter
        );

        (uint256 protocolFee, uint256 lpFee) = _estimateFees(baseCost);
        totalCost = baseCost + protocolFee + lpFee;

        priceImpact = LMSRMath.calculatePriceImpact(
            outcomeQuantities,
            outcomeIndex,
            int256(shares),
            market.liquidityParameter
        );

        return (shares, totalCost, priceImpact);
    }

    /**
     * @notice Simulate sell order
     * @param outcomeIndex Outcome to sell
     * @param sharesToSell Shares to sell
     * @return payout Payout that would be received
     * @return priceImpact Price impact in basis points
     */
    function simulateSell(
        uint8 outcomeIndex,
        uint256 sharesToSell
    ) external view returns (uint256 payout, uint256 priceImpact) {
        uint256 basePayout = LMSRMath.calculateSellPayout(
            outcomeQuantities,
            outcomeIndex,
            sharesToSell,
            market.liquidityParameter
        );

        (uint256 protocolFee, uint256 lpFee) = _estimateFees(basePayout);
        payout = basePayout - protocolFee - lpFee;

        priceImpact = LMSRMath.calculatePriceImpact(
            outcomeQuantities,
            outcomeIndex,
            -int256(sharesToSell),
            market.liquidityParameter
        );

        return (payout, priceImpact);
    }

    /**
     * @notice Get comprehensive market state
     * @return info Market information
     * @return prices Current outcome prices
     * @return quantities Current LMSR quantities
     */
    function getMarketState()
        external
        view
        returns (
            MarketInfo memory info,
            uint256[] memory prices,
            uint256[] memory quantities
        )
    {
        info = market;
        prices = LMSRMath.calculatePrices(
            outcomeQuantities,
            market.liquidityParameter
        );
        quantities = outcomeQuantities;

        return (info, prices, quantities);
    }

    /**
     * @notice Get user's position
     * @param user User address
     * @return balances User's shares for each outcome
     * @return currentValue Current market value of position
     * @return potentialWinnings Max potential winnings
     */
    function getUserPosition(
        address user
    )
        external
        view
        returns (
            uint256[] memory balances,
            uint256 currentValue,
            uint256 potentialWinnings
        )
    {
        balances = outcomeToken.balanceOfAll(user);
        uint256[] memory prices = LMSRMath.calculatePrices(
            outcomeQuantities,
            market.liquidityParameter
        );

        // Calculate current value
        for (uint256 i = 0; i < balances.length; i++) {
            currentValue += (balances[i] * prices[i]) / 1e18;
        }

        // Potential winnings = max balance (if that outcome wins)
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] > potentialWinnings) {
                potentialWinnings = balances[i];
            }
        }

        return (balances, currentValue, potentialWinnings);
    }

    /**
     * @notice Check for arbitrage opportunities
     * @return hasArbitrage True if arbitrage exists
     * @return costDifference Cost difference
     */
    function checkArbitrage()
        external
        view
        returns (bool hasArbitrage, uint256 costDifference)
    {
        uint256[] memory prices = LMSRMath.calculatePrices(
            outcomeQuantities,
            market.liquidityParameter
        );
        return CompleteSetLib.checkArbitrage(prices);
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @dev Binary search to find shares for given cost
     */
    function _calculateSharesForCost(
        uint8 outcomeIndex,
        uint256 maxCost
    ) internal view returns (uint256 shares) {
        uint256 low = 0;
        uint256 high = maxCost * 2; // Upper bound estimate

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            uint256 cost = LMSRMath.calculateBuyCost(
                outcomeQuantities,
                outcomeIndex,
                mid,
                market.liquidityParameter
            );

            if (cost <= maxCost) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    /**
     * @dev Estimate fees for a trade amount
     */
    function _estimateFees(
        uint256 amount
    ) internal view returns (uint256 protocolFee, uint256 lpFee) {
        (, uint256 protocolFeeBps, uint256 lpFeeBps) = feeManager
            .getCurrentFees(address(this));
        protocolFee = (amount * protocolFeeBps) / 10000;
        lpFee = (amount * lpFeeBps) / 10000;
        return (protocolFee, lpFee);
    }
}
