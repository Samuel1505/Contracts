// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title OutcomeToken
 * @notice ERC1155 token representing shares in market outcomes
 * @dev Gas-efficient: All outcome shares for a market use single contract
 * Token ID = outcome index (0, 1, 2, ...)
 * Only the associated market can mint/burn
 */
contract OutcomeToken is ERC1155 {
    address public immutable market;
    bytes32 public metadataURI; // IPFS CID containing market metadata
    uint256 public numOutcomes;

    modifier onlyMarket() {
        if (msg.sender != market) revert Errors.OnlyMarket();
        _;
    }

    /**
     * @param marketAddress The market contract that can mint/burn
     * @param _metadataURI IPFS CID containing market metadata
     * @param _numOutcomes Number of outcomes
     */
    constructor(
        address marketAddress,
        bytes32 _metadataURI,
        uint256 _numOutcomes
    ) ERC1155("") {
        if (marketAddress == address(0)) revert Errors.InvalidAddress();
        if (_numOutcomes == 0) revert Errors.InvalidOutcomeCount();

        market = marketAddress;
        metadataURI = _metadataURI;
        numOutcomes = _numOutcomes;
    }

    /**
     * @notice Mint outcome tokens (only market)
     * @param to Recipient address
     * @param outcomeId Outcome index
     * @param amount Amount to mint
     */
    function mint(
        address to,
        uint256 outcomeId,
        uint256 amount
    ) external onlyMarket {
        _mint(to, outcomeId, amount, "");
    }

    /**
     * @notice Mint complete set (all outcomes) to user
     * @param to Recipient address
     * @param amount Number of complete sets
     */
    function mintCompleteSet(address to, uint256 amount) external onlyMarket {
        uint256[] memory ids = new uint256[](numOutcomes);
        uint256[] memory amounts = new uint256[](numOutcomes);

        for (uint256 i = 0; i < numOutcomes; i++) {
            ids[i] = i;
            amounts[i] = amount;
        }

        _mintBatch(to, ids, amounts, "");
    }

    /**
     * @notice Burn outcome tokens (only market)
     * @param from Address to burn from
     * @param outcomeId Outcome index
     * @param amount Amount to burn
     */
    function burn(
        address from,
        uint256 outcomeId,
        uint256 amount
    ) external onlyMarket {
        _burn(from, outcomeId, amount);
    }

    /**
     * @notice Burn complete set (all outcomes) from user
     * @param from Address to burn from
     * @param amount Number of complete sets
     */
    function burnCompleteSet(address from, uint256 amount) external onlyMarket {
        uint256[] memory ids = new uint256[](numOutcomes);
        uint256[] memory amounts = new uint256[](numOutcomes);

        for (uint256 i = 0; i < numOutcomes; i++) {
            ids[i] = i;
            amounts[i] = amount;
        }

        _burnBatch(from, ids, amounts);
    }

    /**
     * @notice Get user's balances for all outcomes
     * @param user Address to query
     * @return balances Array of balances
     */
    function balanceOfAll(
        address user
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](numOutcomes);

        for (uint256 i = 0; i < numOutcomes; i++) {
            balances[i] = balanceOf(user, i);
        }

        return balances;
    }

    /**
     * @notice Get all outcome names
     * @return names Array of outcome names
     */
    function getAllOutcomeNames()
        external
        view
        returns (string[] memory names)
    {
        // Outcome names are stored in IPFS metadata, not on-chain
        // Fetch from metadataURI to get all outcome names
        // This function returns empty array - use frontend to fetch from IPFS
        names = new string[](numOutcomes);
        return names;
    }

    /**
     * @notice Check if user has a complete set
     * @param user Address to check
     * @return hasSet True if user has at least 1 complete set
     * @return numSets Number of complete sets user has
     */
    function hasCompleteSet(
        address user
    ) external view returns (bool hasSet, uint256 numSets) {
        numSets = type(uint256).max;

        for (uint256 i = 0; i < numOutcomes; i++) {
            uint256 balance = balanceOf(user, i);
            if (balance < numSets) {
                numSets = balance;
            }
        }

        if (numSets == type(uint256).max) {
            numSets = 0;
        }

        hasSet = numSets > 0;
        return (hasSet, numSets);
    }

    /**
     * @notice Override URI to return metadata
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (tokenId >= numOutcomes) revert Errors.InvalidOutcome();

        // Return metadata URI (can be updated to IPFS/API later)
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    _encodeMetadata(tokenId)
                )
            );
    }

    /**
     * @dev Encode metadata for outcome token
     * Returns minimal on-chain metadata pointing to IPFS
     */
    function _encodeMetadata(
        uint256 tokenId
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '{"name":"Outcome #',
                    _toString(tokenId),
                    '","description":"Prediction market outcome share',
                    '","outcome_id":',
                    _toString(tokenId),
                    ',"market":"',
                    _toAsciiString(market),
                    '","metadata_uri":"',
                    _bytes32ToHex(metadataURI),
                    '"}'
                )
            );
    }

    /**
     * @dev Convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @dev Convert address to ASCII string
     */
    function _toAsciiString(
        address addr
    ) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(2 + data.length * 2);

        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    /**
     * @dev Convert bytes32 to hex string (for IPFS CID)
     */
    function _bytes32ToHex(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
