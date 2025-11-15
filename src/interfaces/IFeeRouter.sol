// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IFeeRouter
 * @notice Interface for fee collection and distribution
 */
interface IFeeRouter {
    // Events
    event FeeCollected(address indexed market, uint256 amount);
    event FeesWithdrawn(address indexed treasury, uint256 amount);
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event FeePercentUpdated(uint256 oldPercent, uint256 newPercent);

    // Functions
    function registerMarket(address market) external;

    function collectFee(uint256 amount) external;

    function withdrawFees() external;

    function setTreasury(address newTreasury) external;

    function setFeePercent(uint256 newFeeBps) external;

    // Getters
    function getTotalFeesCollected() external view returns (uint256);

    function getMarketFees(address market) external view returns (uint256);

    function treasury() external view returns (address);

    function protocolFeeBps() external view returns (uint256);

    function collateralToken() external view returns (address);
}
