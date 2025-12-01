# BlockDAG Deployment Guide

This guide walks you through deploying PulseDelta contracts on the BlockDAG blockchain.

## Prerequisites

### 1. Development Environment

- **Foundry** (latest version)
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```

- **Node.js** (optional, for scripts)
  ```bash
  node --version  # v18+ recommended
  ```

### 2. BlockDAG Network Setup

#### Network Details

**BlockDAG Primordial (Mainnet):**
- Chain ID: `1043`
- RPC URL: `https://rpc.primordial.bdagscan.com`
- Explorer: `https://primordial.bdagscan.com`
- Gas Price: `1 Gwei` (1000000000 wei)
- Gas Limit: `8000000`

**BlockDAG Testnet:**
- Chain ID: `TODO` (check BlockDAG documentation)  
- RPC URL: `TODO` (check BlockDAG documentation)
- Explorer: `TODO` (check BlockDAG documentation)
- Faucet: Use BlockDAG faucet to get test BDAG tokens

#### Add BlockDAG to MetaMask

1. Open MetaMask → Settings → Networks → Add Network
2. Fill in BlockDAG network details (see above)
3. Save and switch to BlockDAG network

### 3. Required Accounts & Addresses

Before deployment, prepare:

- **Deployer Account**: Account with BDAG for gas fees
  - Private key (keep secure!)
  - Should have enough BDAG for deployment (~0.1-0.5 BDAG estimated)

- **Treasury Address**: Receives protocol fees
  - Multi-sig recommended for production

- **Oracle Address**: Resolves markets
  - Can be EOA or contract
  - Must be able to call `resolveMarket()` on markets

- **Admin Address**: Factory admin
  - Can update oracle, pause markets
  - Multi-sig recommended for production

### 4. Environment Variables

Create a `.env` file in the project root:

```bash
# Deployer private key (with 0x prefix)
PRIVATE_KEY=0x...

# Addresses (with 0x prefix)
TREASURY_ADDRESS=0x...
ORACLE_ADDRESS=0x...
ADMIN_ADDRESS=0x...

# BlockDAG RPC URL (replace with actual BlockDAG RPC)
RPC_URL=https://mainnet.blockdag.network
# For testnet: https://testnet.blockdag.network

# Block Explorer API key (for verification, optional)
BLOCKDAG_EXPLORER_API_KEY=...
```

**⚠️ Security Warning**: Never commit `.env` file to git! Add it to `.gitignore`.

## Deployment Steps

### Step 1: Install Dependencies

```bash
# Install Foundry dependencies
forge install

# Build contracts
forge build
```

### Step 2: Test Contracts

```bash
# Run all tests
forge test

# Run with gas reports
forge test --gas-report
```

### Step 3: Configure foundry.toml

The `foundry.toml` is already configured with BlockDAG Primordial network:
- RPC endpoint: `primordial`
- Chain ID: `1043`
- Block explorer verification configured

You can use the `primordial` endpoint directly:
```bash
forge script script/Deploy.s.sol --rpc-url primordial ...
```

### Step 4: Deploy Contracts

#### Testnet Deployment

```bash
# Load environment variables
source .env

# Deploy to Primordial (use --rpc-url primordial or the full URL)
forge script script/Deploy.s.sol \
  --rpc-url primordial \
  --gas-price 1000000000 \
  --gas-limit 8000000 \
  --broadcast \
  --verify \
  --etherscan-api-key "no-api-key-needed"

# Alternative: Use environment variable for RPC
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --gas-price 1000000000 \
  --gas-limit 8000000 \
  --broadcast \
  --verify
```

#### Mainnet Deployment

```bash
# Deploy to Primordial mainnet (use --slow for safety)
forge script script/Deploy.s.sol \
  --rpc-url primordial \
  --gas-price 1000000000 \
  --gas-limit 8000000 \
  --broadcast \
  --verify \
  --etherscan-api-key "no-api-key-needed" \
  --slow

# With delay between transactions for safety
forge script script/Deploy.s.sol \
  --rpc-url primordial \
  --gas-price 1000000000 \
  --gas-limit 8000000 \
  --broadcast \
  --verify \
  --slow \
  --resume  # Resume if interrupted
```

### Step 5: Save Deployment Addresses

After deployment, save the contract addresses:

```bash
# Example output addresses - SAVE THESE!
Collateral (wDAG): 0x...
FeeManager: 0x...
SocialPredictions: 0x...
Market Implementation: 0x...
Factory: 0x...
```

Create a `deployments.json` file:

```json
{
  "network": "blockdag-mainnet",
  "deployedAt": "2024-01-01T00:00:00Z",
  "contracts": {
    "wDAG": "0x...",
    "FeeManager": "0x...",
    "SocialPredictions": "0x...",
    "CategoricalMarket": "0x...",
    "CategoricalMarketFactory": "0x..."
  }
}
```

## Post-Deployment Checklist

### Immediate Actions

- [ ] **Verify Contracts on Block Explorer**
  - Visit BlockDAG block explorer: https://primordial.bdagscan.com
  - Contracts should auto-verify if `--verify` flag was used
  - Manually verify if needed using the explorer interface

- [ ] **Transfer Ownership**
  ```bash
  # Transfer wDAG ownership to multisig
  # Transfer Factory ownership to multisig
  # Transfer FeeManager ownership to multisig
  ```

- [ ] **Register Markets in FeeManager**
  - Factory automatically registers markets, but verify

- [ ] **Configure Fee Parameters** (if needed)
  - Update base fees
  - Set LP reward multipliers
  - Configure treasury split

### Testing

- [ ] **Create Test Market**
  ```solidity
  // Via factory
  factory.createMarket(
    metadataURI,  // IPFS CID
    numOutcomes,  // 2-10
    resolutionTime,
    initialLiquidity
  );
  ```

- [ ] **Test Trading**
  - Buy shares
  - Sell shares
  - Mint complete set
  - Burn complete set

- [ ] **Test Liquidity**
  - Add liquidity
  - Remove liquidity
  - Claim LP rewards

- [ ] **Test Resolution**
  - Resolve market (as oracle)
  - Claim winnings
  - Verify final state

### Security & Monitoring

- [ ] **Set up Event Indexer**
  - Monitor `MarketCreated` events
  - Track `TradeExecuted` events
  - Monitor `MarketResolved` events

- [ ] **Monitor Gas Usage**
  - Track transaction costs
  - Optimize if needed

- [ ] **Set up Alerts**
  - High-value trades
  - Unusual activity
  - Contract upgrades

## Gas Cost Estimates

Based on Foundry gas reports:

| Operation | Estimated Gas |
|-----------|---------------|
| Deploy wDAG | ~800,000 |
| Deploy FeeManager | ~1,200,000 |
| Deploy SocialPredictions | ~600,000 |
| Deploy Market Implementation | ~2,500,000 |
| Deploy Factory | ~2,000,000 |
| **Total Deployment** | **~7,100,000** |

## Contract Interaction Examples

### Create a Market

```solidity
// 1. Prepare IPFS metadata
// Upload metadata to IPFS and get CID
bytes32 metadataURI = "0x..." // IPFS CID

// 2. Call factory
factory.createMarket(
    metadataURI,     // IPFS CID
    2,              // 2 outcomes (Yes/No)
    block.timestamp + 30 days, // Resolution time
    10000 * 1e18    // Initial liquidity (10000 wDAG)
);
```

### Buy Shares

```solidity
// Approve collateral
wDAG.approve(marketAddress, amount);

// Buy shares for outcome 0
CategoricalMarket(market).buyShares(0, minShares, maxCost);
```

### Add Liquidity

```solidity
// Approve collateral
wDAG.approve(marketAddress, amount);

// Add liquidity
CategoricalMarket(market).addLiquidity(amount);
```

## Troubleshooting

### Common Issues

1. **"Insufficient funds"**
   - Ensure deployer account has enough BDAG for gas

2. **"Nonce too high"**
   - Reset account nonce or wait for pending transactions

3. **"Contract verification failed"**
   - Verify compiler version matches
   - Ensure all libraries are verified first
   - Check constructor arguments

4. **"Transaction reverted"**
   - Check constructor parameters
   - Verify all addresses are valid
   - Ensure zero addresses are intentional

### Getting Help

- Check BlockDAG documentation: [docs.blockdagnetwork.io](https://docs.blockdagnetwork.io)
- BlockDAG Discord/Telegram community
- Review contract events for error details

## Additional Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [BlockDAG Developer Docs](https://docs.blockdagnetwork.io)
- [IPFS Metadata Guide](./IPFS_METADATA_SPEC.md)
- [Contract Documentation](./README.md)

## Notes

- BlockDAG is EVM-compatible, so standard Ethereum tools work
- Use testnet extensively before mainnet deployment
- Consider using a multisig for ownership
- Keep private keys secure and never commit to git
- Monitor gas prices - BlockDAG may have different gas costs than Ethereum

