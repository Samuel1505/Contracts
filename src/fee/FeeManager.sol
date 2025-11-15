// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DynamicFeeLib} from "../libraries/DynamicFeeLib.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title FeeManager
 * @notice Manages protocol and LP fees with dynamic adjustment and tiered rewards
 * @dev Two-tier fee system:
 * - Protocol fees → Treasury
 * - LP fees → Distributed to LPs based on their share and bonuses
 */
contract FeeManager is Ownable, ReentrancyGuard {
    struct LPInfo {
        uint256 liquidityProvided;
        uint256 lpTokens;
        uint256 entryTime;
        uint256 rewardsEarned;
        uint256 rewardsClaimed;
    }

    struct MarketFeeStats {
        uint256 totalProtocolFees;
        uint256 totalLPFees;
        uint256 totalVolume;
        uint256 createdAt;
    }

    address public immutable collateralToken;
    address public treasury;

    // Market fee tracking
    mapping(address => MarketFeeStats) public marketStats;
    mapping(address => bool) public isMarket;

    // LP tracking per market
    mapping(address => mapping(address => LPInfo)) public lpInfo; // market => user => info
    mapping(address => uint256) public marketLPFeePools; // market => unclaimed LP fees
    mapping(address => uint256) public marketTotalLPTokens; // market => total LP tokens

    // Global stats
    uint256 public totalProtocolFeesCollected;
    uint256 public totalLPFeesDistributed;

    constructor(
        address _collateralToken,
        address _treasury
    ) Ownable(msg.sender) {
        if (_collateralToken == address(0) || _treasury == address(0)) {
            revert Errors.InvalidAddress();
        }

        collateralToken = _collateralToken;
        treasury = _treasury;
    }

    /**
     * @notice Register a market
     * @param market Market address
     */
    function registerMarket(address market) external onlyOwner {
        if (market == address(0)) revert Errors.InvalidAddress();
        isMarket[market] = true;
        marketStats[market].createdAt = block.timestamp;
        emit Events.MarketRegistered(market);
    }

    /**
     * @notice Collect fees from a trade
     * @param market Market address
     * @param tradeAmount Trade amount
     * @return protocolFee Protocol fee amount
     * @return lpFee LP fee amount
     */
    function collectTradeFees(
        address market,
        uint256 tradeAmount
    ) external returns (uint256 protocolFee, uint256 lpFee) {
        if (!isMarket[msg.sender]) revert Errors.OnlyMarket();
        if (tradeAmount == 0) revert Errors.ZeroAmount();

        MarketFeeStats storage stats = marketStats[market];

        // Calculate dynamic fees
        (, uint256 protocolFeeBps, uint256 lpFeeBps) = DynamicFeeLib
            .calculateDynamicFee(
                stats.totalVolume,
                marketTotalLPTokens[market],
                block.timestamp - stats.createdAt
            );

        protocolFee = (tradeAmount * protocolFeeBps) / 10000;
        lpFee = (tradeAmount * lpFeeBps) / 10000;

        // Update stats
        stats.totalProtocolFees += protocolFee;
        stats.totalLPFees += lpFee;
        stats.totalVolume += tradeAmount;

        totalProtocolFeesCollected += protocolFee;
        totalLPFeesDistributed += lpFee;

        // Add LP fees to pool for distribution
        marketLPFeePools[market] += lpFee;

        // Transfer fees from market
        if (protocolFee + lpFee > 0) {
            bool success = IERC20(collateralToken).transferFrom(
                msg.sender,
                address(this),
                protocolFee + lpFee
            );
            if (!success) revert Errors.FeeTransferFailed();
        }

        emit Events.FeeCollected(market, protocolFee + lpFee);

        return (protocolFee, lpFee);
    }

    /**
     * @notice Register LP position
     * @param market Market address
     * @param user LP address
     * @param liquidityAmount Liquidity amount
     * @param lpTokensAmount LP tokens minted
     */
    function registerLP(
        address market,
        address user,
        uint256 liquidityAmount,
        uint256 lpTokensAmount
    ) external {
        if (!isMarket[msg.sender]) revert Errors.OnlyMarket();

        LPInfo storage info = lpInfo[market][user];

        if (info.entryTime == 0) {
            info.entryTime = block.timestamp;
        }

        info.liquidityProvided += liquidityAmount;
        info.lpTokens += lpTokensAmount;

        marketTotalLPTokens[market] += lpTokensAmount;
    }

    /**
     * @notice Unregister LP position (remove liquidity)
     * @param market Market address
     * @param user LP address
     * @param lpTokensAmount LP tokens to remove
     */
    function unregisterLP(
        address market,
        address user,
        uint256 lpTokensAmount
    ) external {
        if (!isMarket[msg.sender]) revert Errors.OnlyMarket();

        LPInfo storage info = lpInfo[market][user];

        if (info.lpTokens < lpTokensAmount) revert Errors.InvalidLPAmount();

        // Claim any pending rewards before removing
        _claimLPRewards(market, user);

        // Proportionally reduce liquidity
        uint256 liquidityToRemove = (info.liquidityProvided * lpTokensAmount) /
            info.lpTokens;

        info.lpTokens -= lpTokensAmount;
        info.liquidityProvided -= liquidityToRemove;

        marketTotalLPTokens[market] -= lpTokensAmount;
    }

    /**
     * @notice Claim LP rewards
     * @param market Market address
     */
    function claimLPRewards(address market) external nonReentrant {
        uint256 rewards = _claimLPRewards(market, msg.sender);
        if (rewards == 0) revert Errors.NothingToClaim();
    }

    /**
     * @notice Withdraw protocol fees to treasury
     */
    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 balance = IERC20(collateralToken).balanceOf(address(this));

        // Calculate protocol fees available (total - LP fee pools)
        uint256 totalLPFeesInPools = 0;
        // Note: In production, track markets array to iterate

        uint256 protocolFeesAvailable = balance - totalLPFeesInPools;
        if (protocolFeesAvailable == 0) revert Errors.ZeroAmount();

        bool success = IERC20(collateralToken).transfer(
            treasury,
            protocolFeesAvailable
        );
        if (!success) revert Errors.FeeTransferFailed();

        emit Events.FeesWithdrawn(treasury, protocolFeesAvailable);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert Errors.InvalidAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit Events.TreasuryUpdated(oldTreasury, newTreasury);
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @dev Internal function to claim LP rewards
     */
    function _claimLPRewards(
        address market,
        address user
    ) internal returns (uint256 rewards) {
        LPInfo storage info = lpInfo[market][user];

        if (info.lpTokens == 0) return 0;

        // Calculate base rewards (proportional to LP share)
        uint256 totalLPTokens = marketTotalLPTokens[market];
        uint256 lpFeePool = marketLPFeePools[market];

        if (totalLPTokens == 0 || lpFeePool == 0) return 0;

        uint256 baseRewards = (lpFeePool * info.lpTokens) / totalLPTokens;

        // Apply multiplier based on time staked and contribution
        uint256 timeStaked = block.timestamp - info.entryTime;
        uint256 multiplier = DynamicFeeLib.calculateLPRewardMultiplier(
            info.liquidityProvided,
            totalLPTokens,
            timeStaked
        );

        rewards = (baseRewards * multiplier) / 1e18;

        // Update tracking
        info.rewardsEarned += rewards;
        info.rewardsClaimed += rewards;

        // Reduce pool
        marketLPFeePools[market] -= baseRewards; // Reduce by base, not multiplier amount

        // Transfer rewards
        if (rewards > 0) {
            bool success = IERC20(collateralToken).transfer(user, rewards);
            if (!success) revert Errors.FeeTransferFailed();
        }

        return rewards;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get pending LP rewards for a user
     * @param market Market address
     * @param user LP address
     * @return pendingRewards Amount of claimable rewards
     */
    function getPendingLPRewards(
        address market,
        address user
    ) external view returns (uint256 pendingRewards) {
        LPInfo memory info = lpInfo[market][user];

        if (info.lpTokens == 0) return 0;

        uint256 totalLPTokens = marketTotalLPTokens[market];
        uint256 lpFeePool = marketLPFeePools[market];

        if (totalLPTokens == 0 || lpFeePool == 0) return 0;

        uint256 baseRewards = (lpFeePool * info.lpTokens) / totalLPTokens;

        uint256 timeStaked = block.timestamp - info.entryTime;
        uint256 multiplier = DynamicFeeLib.calculateLPRewardMultiplier(
            info.liquidityProvided,
            totalLPTokens,
            timeStaked
        );

        pendingRewards = (baseRewards * multiplier) / 1e18;

        return pendingRewards;
    }

    /**
     * @notice Get LP info for a user in a market
     * @param market Market address
     * @param user LP address
     * @return info LP information
     * @return pendingRewards Pending rewards
     * @return apr Estimated APR in basis points
     */
    function getLPInfo(
        address market,
        address user
    )
        external
        view
        returns (LPInfo memory info, uint256 pendingRewards, uint256 apr)
    {
        info = lpInfo[market][user];

        // Calculate pending rewards
        if (info.lpTokens > 0) {
            uint256 totalLPTokens = marketTotalLPTokens[market];
            uint256 lpFeePool = marketLPFeePools[market];

            if (totalLPTokens > 0 && lpFeePool > 0) {
                uint256 baseRewards = (lpFeePool * info.lpTokens) /
                    totalLPTokens;
                uint256 timeStaked = block.timestamp - info.entryTime;
                uint256 multiplier = DynamicFeeLib.calculateLPRewardMultiplier(
                    info.liquidityProvided,
                    totalLPTokens,
                    timeStaked
                );

                pendingRewards = (baseRewards * multiplier) / 1e18;
            }

            // Estimate APR based on recent fees
            MarketFeeStats memory stats = marketStats[market];
            if (info.liquidityProvided > 0 && stats.totalLPFees > 0) {
                uint256 marketAge = block.timestamp - stats.createdAt;
                if (marketAge > 0) {
                    // Annualize the return
                    uint256 yearlyFees = (stats.totalLPFees * 365 days) /
                        marketAge;
                    uint256 userYearlyFees = (yearlyFees * info.lpTokens) /
                        totalLPTokens;
                    apr = (userYearlyFees * 10000) / info.liquidityProvided;
                }
            }
        }

        return (info, pendingRewards, apr);
    }

    /**
     * @notice Get market fee stats
     * @param market Market address
     * @return stats Market fee statistics
     */
    function getMarketFeeStats(
        address market
    ) external view returns (MarketFeeStats memory stats) {
        return marketStats[market];
    }

    /**
     * @notice Get current dynamic fees for a market
     * @param market Market address
     * @return totalFeeBps Total fee in bps
     * @return protocolFeeBps Protocol fee in bps
     * @return lpFeeBps LP fee in bps
     */
    function getCurrentFees(
        address market
    )
        external
        view
        returns (uint256 totalFeeBps, uint256 protocolFeeBps, uint256 lpFeeBps)
    {
        MarketFeeStats memory stats = marketStats[market];
        return
            DynamicFeeLib.calculateDynamicFee(
                stats.totalVolume,
                marketTotalLPTokens[market],
                block.timestamp - stats.createdAt
            );
    }
}
