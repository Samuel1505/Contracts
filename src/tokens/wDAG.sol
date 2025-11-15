// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title wDAG
 * @notice Wrapped DAG token - ERC20 collateral token for the prediction market
 * @dev For testing purposes, includes mint function. In production, this would be the actual wrapped token
 */
contract wDAG is ERC20, Ownable {
    constructor() ERC20("Wrapped DAG", "wDAG") Ownable(msg.sender) {}

    /**
     * @notice Mint tokens to an address (for testing)
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Decimals for wDAG token
     * @return 18 decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

