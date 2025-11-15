// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title LPToken
 * @notice ERC20 liquidity provider token for a specific market
 * @dev Only the associated market contract can mint/burn
 */
contract LPToken is ERC20 {
    address public immutable market;

    modifier onlyMarket() {
        if (msg.sender != market) revert Errors.OnlyMarket();
        _;
    }

    /**
     * @param marketAddress The market contract that can mint/burn this token
     * @param metadataURI IPFS CID (not used in name, just for reference)
     */
    constructor(address marketAddress, bytes32 metadataURI) ERC20(
        string.concat("PulseDelta LP - ", _toShortString(marketAddress)),
        string.concat("PD-LP-", _toShortString(marketAddress))
    ) {
        if (marketAddress == address(0)) revert Errors.InvalidAddress();
        market = marketAddress;
        // metadataURI stored in market contract, not here
    }

    /**
     * @notice Mint LP tokens (only callable by market)
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyMarket {
        _mint(to, amount);
    }

    /**
     * @notice Burn LP tokens (only callable by market)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyMarket {
        _burn(from, amount);
    }

    /**
     * @notice Decimals for LP token
     * @return 18 decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev Truncate a string to maxLength characters
     */
    function _truncate(string memory str, uint256 maxLength)
        private
        pure
        returns (string memory)
    {
        bytes memory strBytes = bytes(str);
        if (strBytes.length <= maxLength) {
            return str;
        }

        bytes memory truncated = new bytes(maxLength);
        for (uint256 i = 0; i < maxLength; i++) {
            truncated[i] = strBytes[i];
        }
        return string(truncated);
    }

    /**
     * @dev Convert address to short string for symbol
     */
    function _toShortString(address addr) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(8);

        for (uint256 i = 0; i < 4; i++) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}

