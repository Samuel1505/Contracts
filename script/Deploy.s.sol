// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {wDAG} from "../src/tokens/wDAG.sol";
import {FeeManager} from "../src/fee/FeeManager.sol";
import {SocialPredictions} from "../src/core/SocialPredictions.sol";
import {CategoricalMarket} from "../src/core/CategoricalMarket.sol";
import {CategoricalMarketFactory} from "../src/core/CategoricalMarketFactory.sol";

/**
 * @title DeployScript
 * @notice Deployment script for PulseDelta contracts on BlockDAG
 * @dev Deploys contracts in correct order:
 * 1. wDAG (collateral token)
 * 2. FeeManager
 * 3. SocialPredictions
 * 4. CategoricalMarket (implementation)
 * 5. CategoricalMarketFactory
 */
contract DeployScript is Script {
    /**
     * @notice Environment variables - set these before deployment
     * 
     * PRIVATE_KEY - Deployer private key (required)
     *   - Account that will deploy contracts and pay gas fees
     *   - Should have sufficient BDAG balance for deployment
     * 
     * TREASURY_ADDRESS - Address to receive protocol fees (optional, defaults to deployer)
     *   - Receives all protocol fees collected by FeeManager
     *   - Can be updated later via FeeManager.setTreasury()
     *   - RECOMMENDED: Multi-sig wallet for production
     *   - For testing: Can use deployer address
     * 
     * ORACLE_ADDRESS - Oracle address for market resolution (optional, defaults to deployer)
     *   - The ONLY address that can call resolveMarket() on markets
     *   - Determines the winning outcome for each market
     *   - Can be an EOA (Externally Owned Account) or a smart contract
     *   - Can be updated later via Factory.setOracle() (only by owner)
     *   - RECOMMENDED: 
     *     - Production: Multi-sig wallet or governance contract
     *     - Testing: Deployer address or test account
     *   - SECURITY: This address has significant power - choose carefully!
     * 
     * ADMIN_ADDRESS - Admin address for factory operations (optional, defaults to deployer)
     *   - Has admin privileges on the Factory contract
     *   - Can update oracle address (via setOracle)
     *   - Can be updated later via Factory.setAdmin() (only by owner)
     *   - RECOMMENDED: Multi-sig wallet for production
     *   - For testing: Can use deployer address
     */

    // Contract addresses for verification
    address public collateralAddress;
    address public feeManagerAddress;
    address public socialPredictionsAddress;
    address public implementationAddress;
    address public factoryAddress;


    function run() external {
        // Read environment variables
        // Private key can be provided with or without 0x prefix
        bytes32 privateKeyBytes = vm.envBytes32("PRIVATE_KEY");
        uint256 deployerPrivateKey = uint256(privateKeyBytes);
        address deployer = vm.addr(deployerPrivateKey);
        
        // Read addresses (default to deployer for testing convenience)
        // WARNING: For production, set these to appropriate addresses (multi-sig recommended)
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address oracle = vm.envOr("ORACLE_ADDRESS", deployer);
        address admin = vm.envOr("ADMIN_ADDRESS", deployer);

        console.log("=== PulseDelta Deployment on BlockDAG ===");
        console.log("Deployer:", deployer);
        console.log("Treasury (receives protocol fees):", treasury);
        console.log("Oracle (resolves markets):", oracle);
        console.log("Admin (factory admin):", admin);
        
        // Warn if using deployer for production addresses
        if (treasury == deployer || oracle == deployer || admin == deployer) {
            console.log("\n[WARNING] Using deployer address for treasury/oracle/admin.");
            console.log("For production, use multi-sig wallets or governance contracts!");
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy collateral token (wDAG)
        console.log("\n1. Deploying wDAG token...");
        wDAG collateral = new wDAG();
        collateralAddress = address(collateral);
        console.log("   wDAG deployed at:", collateralAddress);

        // 2. Deploy fee manager
        console.log("\n2. Deploying FeeManager...");
        FeeManager feeManager = new FeeManager(address(collateral), treasury);
        feeManagerAddress = address(feeManager);
        console.log("   FeeManager deployed at:", feeManagerAddress);

        // 3. Deploy social predictions
        console.log("\n3. Deploying SocialPredictions...");
        SocialPredictions socialPredictions = new SocialPredictions();
        socialPredictionsAddress = address(socialPredictions);
        console.log("   SocialPredictions deployed at:", socialPredictionsAddress);

        // 4. Deploy market implementation
        // Note: outcomeToken and lpToken are set during initialization, use placeholders
        console.log("\n4. Deploying CategoricalMarket implementation...");
        CategoricalMarket implementation = new CategoricalMarket(
            address(collateral),
            address(0), // Will be set during market creation
            address(0), // Will be set during market creation
            address(feeManager),
            address(socialPredictions)
        );
        implementationAddress = address(implementation);
        console.log("   Implementation deployed at:", implementationAddress);

        // 5. Deploy factory
        console.log("\n5. Deploying CategoricalMarketFactory...");
        CategoricalMarketFactory factory = new CategoricalMarketFactory(
            address(implementation),
            address(collateral),
            address(feeManager),
            address(socialPredictions),
            oracle,
            admin
        );
        factoryAddress = address(factory);
        console.log("   Factory deployed at:", factoryAddress);

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Collateral (wDAG):", collateralAddress);
        console.log("FeeManager:", feeManagerAddress);
        console.log("SocialPredictions:", socialPredictionsAddress);
        console.log("Market Implementation:", implementationAddress);
        console.log("Factory:", factoryAddress);
        console.log("\n[SUCCESS] Deployment complete!");
        
        // Verification note
        console.log("\n=== Verification ===");
        console.log("Contracts will be automatically verified if you used --verify flag.");
        console.log("If verification failed, you can manually verify using:");
        console.log("  forge verify-contract <ADDRESS> <CONTRACT_PATH> --chain-id 1043 --rpc-url primordial --etherscan-api-key no-api-key-needed");
        console.log("\nContract addresses stored in script state for easy access.");
        
        console.log("\nNext steps:");
        console.log("1. Verify contracts on BlockDAG explorer (should be automatic with --verify)");
        console.log("2. Transfer ownership to multisig (if applicable)");
        console.log("3. Configure FeeManager parameters");
        console.log("4. Test market creation via Factory");
    }
}

