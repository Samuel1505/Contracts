// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CategoricalMarket} from "./CategoricalMarket.sol";
import {OutcomeToken} from "../tokens/OutcomeToken.sol";
import {LPToken} from "../tokens/LPToken.sol";
import {FeeManager} from "../fee/FeeManager.sol";
import {SocialPredictions} from "./SocialPredictions.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title CategoricalMarketFactory
 * @notice Factory for creating LMSR-based prediction markets with social features
 * @dev Uses minimal proxy pattern for gas-efficient deployment
 */
contract CategoricalMarketFactory is Ownable {
    struct MarketSummary {
        address market;
        address outcomeToken;
        address lpToken;
        bytes32 metadataURI; // IPFS CID - fetch to get question, description, images
        uint256 numOutcomes;
        uint256 resolutionTime;
        CategoricalMarket.MarketStatus status;
        uint256 totalLiquidity;
        uint256[] prices;
    }

    // Immutable references
    address public immutable marketImplementation;
    address public immutable collateralToken;
    address public immutable feeManager;
    address public immutable socialPredictions;

    // Config
    address public admin;
    address public oracleResolver;

    // Market tracking
    mapping(address => bool) public isMarket;
    address[] public allMarkets;
    mapping(address => address) public marketToOutcomeToken;
    mapping(address => address) public marketToLPToken;

    // Constants
    uint256 public constant MIN_INITIAL_LIQUIDITY = 100 * 1e18;
    uint256 public constant MIN_MARKET_DURATION = 1 hours;
    uint256 public constant MAX_OUTCOMES = 10;

    modifier onlyAdmin() {
        if (msg.sender != admin && msg.sender != owner())
            revert Errors.OnlyAdmin();
        _;
    }

    /**
     * @param _marketImplementation CategoricalMarket implementation
     * @param _collateralToken Collateral token (wDAG)
     * @param _feeManager Fee manager address
     * @param _socialPredictions Social predictions contract
     * @param _oracleResolver Oracle address
     * @param _admin Admin address
     */
    constructor(
        address _marketImplementation,
        address _collateralToken,
        address _feeManager,
        address _socialPredictions,
        address _oracleResolver,
        address _admin
    ) Ownable(msg.sender) {
        if (
            _marketImplementation == address(0) ||
            _collateralToken == address(0) ||
            _feeManager == address(0) ||
            _socialPredictions == address(0) ||
            _oracleResolver == address(0) ||
            _admin == address(0)
        ) {
            revert Errors.InvalidAddress();
        }

        marketImplementation = _marketImplementation;
        collateralToken = _collateralToken;
        feeManager = _feeManager;
        socialPredictions = _socialPredictions;
        oracleResolver = _oracleResolver;
        admin = _admin;
    }

    /**
     * @notice Create a new categorical prediction market
     * @param metadataURI IPFS CID containing market metadata (question, description, outcomes, images)
     * @param numOutcomes Number of outcomes (2-10)
     * @param resolutionTime When market can be resolved
     * @param initialLiquidity Initial liquidity to add
     * @return market Address of created market
     * @return outcomeTokenAddr Address of outcome token (ERC1155)
     * @return lpTokenAddr Address of LP token
     */
    function createMarket(
        bytes32 metadataURI,
        uint256 numOutcomes,
        uint256 resolutionTime,
        uint256 initialLiquidity
    )
        external
        onlyAdmin
        returns (address market, address outcomeTokenAddr, address lpTokenAddr)
    {
        // Validations
        if (metadataURI == bytes32(0)) revert Errors.InvalidParameter();
        if (numOutcomes < 2 || numOutcomes > MAX_OUTCOMES) {
            revert Errors.InvalidOutcomeCount();
        }
        if (resolutionTime < block.timestamp + MIN_MARKET_DURATION) {
            revert Errors.ResolutionTimePassed();
        }
        if (initialLiquidity < MIN_INITIAL_LIQUIDITY) {
            revert Errors.InsufficientLiquidity();
        }

        // Generate salt for deterministic deployment
        bytes32 salt = keccak256(
            abi.encodePacked(
                metadataURI,
                numOutcomes,
                resolutionTime,
                block.timestamp,
                allMarkets.length
            )
        );

        // Predict market address before creating it
        market = Clones.predictDeterministicAddress(
            marketImplementation,
            salt
        );

        // Deploy outcome token (ERC1155) with predicted market address
        OutcomeToken outcomeToken = new OutcomeToken(
            market,
            metadataURI,
            numOutcomes
        );
        outcomeTokenAddr = address(outcomeToken);

        // Deploy LP token with predicted market address
        LPToken lpToken = new LPToken(
            market,
            metadataURI
        );
        lpTokenAddr = address(lpToken);

        // Deploy market via minimal proxy with deterministic address
        market = Clones.cloneDeterministic(marketImplementation, salt);

        // Initialize market with token addresses
        CategoricalMarket(market).initialize(
            metadataURI,
            numOutcomes,
            resolutionTime,
            oracleResolver,
            initialLiquidity,
            outcomeTokenAddr,
            lpTokenAddr
        );

        // Register market with fee manager
        FeeManager(feeManager).registerMarket(market);

        // Track market
        isMarket[market] = true;
        allMarkets.push(market);
        marketToOutcomeToken[market] = outcomeTokenAddr;
        marketToLPToken[market] = lpTokenAddr;

        // Add initial liquidity from admin
        if (initialLiquidity > 0) {
            bool success = IERC20(collateralToken).transferFrom(
                msg.sender,
                address(this),
                initialLiquidity
            );
            if (!success) revert Errors.InsufficientCollateral();

            // Approve and add liquidity
            IERC20(collateralToken).approve(market, initialLiquidity);
            CategoricalMarket(market).addLiquidity(initialLiquidity);

            // Transfer LP tokens to admin
            uint256 lpBalance = lpToken.balanceOf(address(this));
            if (lpBalance > 0) {
                lpToken.transfer(msg.sender, lpBalance);
            }
        }

        emit Events.MarketCreated(
            market,
            metadataURI,
            numOutcomes,
            resolutionTime,
            msg.sender
        );

        return (market, outcomeTokenAddr, lpTokenAddr);
    }

    /**
     * @notice Set admin address
     * @param newAdmin New admin
     */
    function setAdmin(address newAdmin) external onlyOwner {
        if (newAdmin == address(0)) revert Errors.InvalidAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit Events.AdminUpdated(oldAdmin, newAdmin);
    }

    /**
     * @notice Set oracle resolver
     * @param newOracle New oracle
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert Errors.InvalidAddress();
        address oldOracle = oracleResolver;
        oracleResolver = newOracle;
        emit Events.OracleUpdated(oldOracle, newOracle);
    }

    // ============================================
    // RICH GETTER FUNCTIONS
    // ============================================

    /**
     * @notice Get all markets
     * @return markets Array of market addresses
     */
    function getAllMarkets() external view returns (address[] memory markets) {
        return allMarkets;
    }

    /**
     * @notice Get market count
     * @return count Total markets created
     */
    function getMarketCount() external view returns (uint256 count) {
        return allMarkets.length;
    }

    /**
     * @notice Get active markets
     * @return markets Array of active market addresses
     */
    function getActiveMarkets()
        external
        view
        returns (address[] memory markets)
    {
        // Count active markets
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allMarkets.length; i++) {
            (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
                allMarkets[i]
            ).getMarketState();

            if (info.status == CategoricalMarket.MarketStatus.ACTIVE) {
                activeCount++;
            }
        }

        // Populate array
        markets = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allMarkets.length; i++) {
            (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
                allMarkets[i]
            ).getMarketState();

            if (info.status == CategoricalMarket.MarketStatus.ACTIVE) {
                markets[index] = allMarkets[i];
                index++;
            }
        }

        return markets;
    }

    /**
     * @notice Get markets by status
     * @param status Status to filter by
     * @return markets Array of markets with that status
     */
    function getMarketsByStatus(
        CategoricalMarket.MarketStatus status
    ) external view returns (address[] memory markets) {
        uint256 count = 0;
        for (uint256 i = 0; i < allMarkets.length; i++) {
            (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
                allMarkets[i]
            ).getMarketState();

            if (info.status == status) {
                count++;
            }
        }

        markets = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allMarkets.length; i++) {
            (CategoricalMarket.MarketInfo memory info, , ) = CategoricalMarket(
                allMarkets[i]
            ).getMarketState();

            if (info.status == status) {
                markets[index] = allMarkets[i];
                index++;
            }
        }

        return markets;
    }

    /**
     * @notice Get market summary
     * @param market Market address
     * @return summary Market summary with all info
     */
    function getMarketSummary(
        address market
    ) external view returns (MarketSummary memory summary) {
        if (!isMarket[market]) revert Errors.InvalidAddress();

        (
            CategoricalMarket.MarketInfo memory info,
            uint256[] memory prices,

        ) = CategoricalMarket(market).getMarketState();

        summary = MarketSummary({
            market: market,
            outcomeToken: marketToOutcomeToken[market],
            lpToken: marketToLPToken[market],
            metadataURI: info.metadataURI,
            numOutcomes: prices.length,
            resolutionTime: info.resolutionTime,
            status: info.status,
            totalLiquidity: info.totalCollateral,
            prices: prices
        });

        return summary;
    }

    /**
     * @notice Get paginated market summaries
     * @param offset Starting index
     * @param limit Max results
     * @return summaries Array of market summaries
     */
    function getMarketSummaries(
        uint256 offset,
        uint256 limit
    ) external view returns (MarketSummary[] memory summaries) {
        if (offset >= allMarkets.length) {
            return new MarketSummary[](0);
        }

        uint256 end = offset + limit;
        if (end > allMarkets.length) {
            end = allMarkets.length;
        }

        uint256 resultLength = end - offset;
        summaries = new MarketSummary[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            address market = allMarkets[offset + i];

            (
                CategoricalMarket.MarketInfo memory info,
                uint256[] memory prices,

            ) = CategoricalMarket(market).getMarketState();

            summaries[i] = MarketSummary({
                market: market,
                outcomeToken: marketToOutcomeToken[market],
                lpToken: marketToLPToken[market],
                metadataURI: info.metadataURI,
                numOutcomes: prices.length,
                resolutionTime: info.resolutionTime,
                status: info.status,
                totalLiquidity: info.totalCollateral,
                prices: prices
            });
        }

        return summaries;
    }

    /**
     * @notice Get recent markets
     * @param count Number of recent markets
     * @return markets Array of recent market addresses
     */
    function getRecentMarkets(
        uint256 count
    ) external view returns (address[] memory markets) {
        if (count == 0 || allMarkets.length == 0) {
            return new address[](0);
        }

        uint256 resultCount = count > allMarkets.length
            ? allMarkets.length
            : count;
        markets = new address[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            markets[i] = allMarkets[allMarkets.length - 1 - i];
        }

        return markets;
    }

    /**
     * @notice Get outcome token for a market
     * @param market Market address
     * @return outcomeToken Outcome token address
     */
    function getOutcomeToken(
        address market
    ) external view returns (address outcomeToken) {
        return marketToOutcomeToken[market];
    }

    /**
     * @notice Get LP token for a market
     * @param market Market address
     * @return lpToken LP token address
     */
    function getLPToken(
        address market
    ) external view returns (address lpToken) {
        return marketToLPToken[market];
    }

    /**
     * @notice Get factory configuration
     * @return _marketImplementation Implementation address
     * @return _collateralToken Collateral token
     * @return _feeManager Fee manager
     * @return _socialPredictions Social predictions contract
     * @return _oracleResolver Oracle
     * @return _admin Admin
     */
    function getFactoryConfig()
        external
        view
        returns (
            address _marketImplementation,
            address _collateralToken,
            address _feeManager,
            address _socialPredictions,
            address _oracleResolver,
            address _admin
        )
    {
        return (
            marketImplementation,
            collateralToken,
            feeManager,
            socialPredictions,
            oracleResolver,
            admin
        );
    }
}
