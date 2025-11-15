# PulseDelta IPFS Metadata Specification

## Market Metadata JSON Structure

### Location

Upload to IPFS and store CID on-chain as `bytes32`

### Format

```json
{
  "version": "1.0",
  "question": "Will Bitcoin reach $100,000 by end of 2024?",
  "description": "This market resolves YES if Bitcoin (BTC) reaches or exceeds $100,000 USD on CoinGecko at any point before midnight UTC on December 31, 2024. Otherwise resolves NO.",
  "category": "Cryptocurrency",
  "tags": ["Bitcoin", "Price Prediction", "Crypto"],
  "image": "ipfs://QmMarketImageHash...",
  "outcomes": [
    {
      "id": 0,
      "name": "Yes",
      "description": "Bitcoin reaches $100k",
      "image": "ipfs://QmOutcomeImageHash1..."
    },
    {
      "id": 1,
      "name": "No",
      "description": "Bitcoin does not reach $100k",
      "image": "ipfs://QmOutcomeImageHash2..."
    }
  ],
  "resolutionSource": "CoinGecko BTC/USD price",
  "resolutionCriteria": "Maximum daily price must reach or exceed $100,000",
  "createdAt": 1700000000,
  "expiresAt": 1735689600
}
```

## Social Prediction Metadata

```json
{
  "version": "1.0",
  "prediction": {
    "outcome": 0,
    "confidence": 85,
    "reasoning": "Technical analysis shows strong support at $90k...",
    "timestamp": 1700000000
  }
}
```

## Comment Metadata

```json
{
  "version": "1.0",
  "content": "I think this market will resolve YES because...",
  "timestamp": 1700000000
}
```

## How to Upload

### Using Pinata (Recommended)

```typescript
const pinata = new PinataSDK(apiKey, apiSecret);
const result = await pinata.pinJSONToIPFS({
  question: "...",
  description: "...",
  // ... rest of metadata
});
const ipfsCID = result.IpfsHash; // Store this on-chain
```

### Using NFT.Storage

```typescript
import { NFTStorage } from 'nft.storage';
const client = new NFTStorage({ token: apiKey });
const metadata = { question: "...", ... };
const cid = await client.storeBlob(new Blob([JSON.stringify(metadata)]));
```

## Frontend Retrieval

```typescript
// Read CID from contract
const ipfsCID = await market.metadataURI();

// Fetch from IPFS gateway
const response = await fetch(`https://ipfs.io/ipfs/${ipfsCID}`);
const metadata = await response.json();

console.log(metadata.question);
console.log(metadata.description);
console.log(metadata.image);
```

## IPFS Gateways

- `https://ipfs.io/ipfs/{CID}`
- `https://gateway.pinata.cloud/ipfs/{CID}`
- `https://cloudflare-ipfs.com/ipfs/{CID}`
- `https://{CID}.ipfs.dweb.link/`

## CID Encoding

Store as bytes32 on-chain:

```solidity
// IPFS CID v0: QmXxx... (46 chars, base58)
// IPFS CID v1: bafxxx... (59+ chars, base32)
// We'll use CID v0 for gas efficiency

bytes32 ipfsCID = bytes32(uint256(keccak256(abi.encodePacked("Qm..."))));
```
