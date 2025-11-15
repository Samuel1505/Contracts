// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ICategoricalMarket
 * @notice Interface for categorical prediction markets
 */
interface ICategoricalMarket {
    // Enums
    enum MarketStatus {
        ACTIVE,
        RESOLVED,
        CANCELLED
    }

    // Structs
    struct MarketInfo {
        string question;
        uint256 totalCollateral;
        uint256 liquidityPool;
        uint256 resolutionTime;
        uint256 createdAt;
        MarketStatus status;
        uint8 winningOutcome;
        address oracleResolver;
    }

    struct OutcomeInfo {
        string name;
        uint256 shareSupply;
    }

    struct UserPosition {
        uint256[] shares;
        uint256 totalValue;
        uint256 potentialWinnings;
    }

    struct UserLiquidity {
        uint256 lpTokens;
        uint256 shareOfPool;
        uint256 claimableCollateral;
    }

    struct MarketState {
        string question;
        string[] outcomeNames;
        uint256[] shareSupplies;
        uint256[] currentPrices;
        uint256 totalLiquidity;
        MarketStatus status;
        uint256 timeToResolution;
    }

    // Events
    event MarketInitialized(
        string question, string[] outcomes, uint256 resolutionTime, address oracle
    );
    event SharesPurchased(
        address indexed user, uint8 indexed outcome, uint256 shares, uint256 cost
    );
    event SharesSold(
        address indexed user, uint8 indexed outcome, uint256 shares, uint256 payout
    );
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 lpTokens, uint256 amount);
    event MarketResolved(uint8 indexed winningOutcome, uint256 timestamp);
    event WinningsClaimed(address indexed user, uint256 amount);
    event MarketCancelled(uint256 timestamp);

    // Core functions
    function initialize(
        string memory question,
        string[] memory outcomeNames,
        uint256 resolutionTime,
        address oracleResolver,
        address collateralToken,
        address feeRouter,
        address lpToken
    ) external;

    function buyShares(uint8 outcomeIndex, uint256 collateralAmount) external;
    function sellShares(uint8 outcomeIndex, uint256 sharesToSell) external;
    function addLiquidity(uint256 amount) external;
    function removeLiquidity(uint256 lpTokens) external;
    function resolveMarket(uint8 winningOutcomeIndex) external;
    function cancelMarket() external;
    function claimWinnings() external;

    // Rich getter functions
    function getUserPosition(address user) external view returns (UserPosition memory);
    function getUserLiquidity(address user) external view returns (UserLiquidity memory);
    function getMarketState() external view returns (MarketState memory);
    function getMarketInfo() external view returns (MarketInfo memory);
    function getOutcomePrices() external view returns (uint256[] memory);
    function getOutcomeInfo(uint8 outcomeIndex) external view returns (OutcomeInfo memory);
    function getAllOutcomes() external view returns (OutcomeInfo[] memory);
    function calculateBuyReturn(uint8 outcome, uint256 collateral)
        external
        view
        returns (uint256 shares, uint256 fee, uint256 priceImpact);
    function calculateSellReturn(uint8 outcome, uint256 shares)
        external
        view
        returns (uint256 collateral, uint256 fee, uint256 priceImpact);
}

