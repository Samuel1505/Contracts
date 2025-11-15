// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICategoricalMarket} from "./ICategoricalMarket.sol";

/**
 * @title IMarketFactory
 * @notice Interface for creating prediction markets
 */
interface IMarketFactory {
    // Structs
    struct MarketSummary {
        address marketAddress;
        string question;
        uint256 resolutionTime;
        ICategoricalMarket.MarketStatus status;
        uint256 totalLiquidity;
    }

    // Events
    event MarketCreated(
        address indexed market,
        string question,
        string[] outcomes,
        uint256 resolutionTime,
        address indexed creator
    );
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // Functions
    function createMarket(
        string memory question,
        string[] memory outcomeNames,
        uint256 resolutionTime,
        uint256 initialLiquidity
    ) external returns (address market);

    function setAdmin(address newAdmin) external;
    function setOracle(address newOracle) external;

    // Rich getters
    function getAllMarkets() external view returns (address[] memory);
    function getMarketCount() external view returns (uint256);
    function isMarket(address market) external view returns (bool);
    function getActiveMarkets()
        external
        view
        returns (address[] memory markets, string[] memory questions, uint256[] memory resolutionTimes);
    function getMarketsByStatus(ICategoricalMarket.MarketStatus status)
        external
        view
        returns (address[] memory);
    function getMarketSummaries(uint256 offset, uint256 limit)
        external
        view
        returns (MarketSummary[] memory);
    function getMarketSummary(address market) external view returns (MarketSummary memory);
}

