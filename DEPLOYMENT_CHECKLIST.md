# BlockDAG Deployment Checklist

Quick reference checklist for deploying PulseDelta contracts on BlockDAG.

## Pre-Deployment

- [ ] **Install Foundry**: `foundryup`
- [ ] **Install Dependencies**: `forge install`
- [ ] **Build Contracts**: `forge build`
- [ ] **Run Tests**: `forge test`
- [ ] **Add BlockDAG Network to MetaMask**
- [ ] **Get Test BDAG** (testnet) or ensure mainnet BDAG balance
- [ ] **Prepare Accounts**:
  - [ ] Deployer account with private key
  - [ ] Treasury address (multisig recommended)
  - [ ] Oracle address
  - [ ] Admin address (multisig recommended)

## Environment Setup

- [ ] **Create `.env` file** with:
  - [ ] `PRIVATE_KEY=0x...`
  - [ ] `TREASURY_ADDRESS=0x...`
  - [ ] `ORACLE_ADDRESS=0x...`
  - [ ] `ADMIN_ADDRESS=0x...`
  - [ ] `RPC_URL=...`
- [ ] **Add `.env` to `.gitignore`**

## Deployment

- [ ] **Testnet Deployment** (test first):
  ```bash
  forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
  ```
- [ ] **Save Contract Addresses** to `deployments.json`
- [ ] **Mainnet Deployment**:
  ```bash
  forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify --slow
  ```

## Post-Deployment

- [ ] **Verify Contracts** on BlockDAG explorer
- [ ] **Transfer Ownership** to multisig:
  - [ ] wDAG owner
  - [ ] Factory owner  
  - [ ] FeeManager owner
- [ ] **Test Market Creation** via Factory
- [ ] **Test Trading** (buy/sell shares)
- [ ] **Test Complete Sets** (mint/burn)
- [ ] **Test Liquidity** (add/remove)
- [ ] **Test Resolution** (resolve market, claim winnings)

## Configuration

- [ ] **Configure FeeManager** parameters (if needed)
- [ ] **Set up Event Indexer** for monitoring
- [ ] **Set up Alerts** for important events
- [ ] **Document Contract Addresses** for team

## Security

- [ ] **Private keys stored securely** (never in git)
- [ ] **Multi-sig wallets configured**
- [ ] **Backup deployment addresses**
- [ ] **Review access controls**
- [ ] **Monitor initial transactions**

---

**Estimated Total Gas**: ~7,100,000 gas units  
**Estimated Cost**: Check BlockDAG gas prices

See [BLOCKDAG_DEPLOYMENT.md](./BLOCKDAG_DEPLOYMENT.md) for detailed instructions.

