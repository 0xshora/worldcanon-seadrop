// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDropUpgradeable } from "./ERC721SeaDropUpgradeable.sol";
import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";



library ImprintStorage {
    struct Layout {
        /// @notice The only address that can burn tokens on this contract.
        address burnAddress;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("seaDrop.contracts.storage.imprint");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

/*
 * @notice This contract uses ERC721SeaDrop,
 *         an ERC721A token contract that is compatible with SeaDrop.
 *         The set burn address is the only sender that can burn tokens.
 */
contract Imprint is ERC721SeaDropUpgradeable {
    using ImprintStorage for ImprintStorage.Layout;

    // SVG container template parts
    bytes private constant SVG_PREFIX = abi.encodePacked(
        "<svg xmlns='http://www.w3.org/2000/svg' width='350' height='350'>",
        "<rect width='100%' height='100%' fill='black'/>",
        "<foreignObject x='10' y='10' width='330' height='330'>",
        "<div xmlns='http://www.w3.org/1999/xhtml' style='color:white;font:20px/1.4 Courier New,monospace;overflow-wrap:anywhere;'>"
    );
    bytes private constant SVG_SUFFIX = "</div></foreignObject></svg>";

    address public svgPrefixPtr;
    address public svgSuffixPtr;

    function __Imprint_init(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) internal onlyInitializing {
        // Initialize ERC721SeaDrop with name, symbol, and allowed SeaDrop
        __ERC721SeaDrop_init(name, symbol, allowedSeaDrop);

        // // Initialize SVG pointers
        svgPrefixPtr = SSTORE2.write(SVG_PREFIX);
        svgSuffixPtr = SSTORE2.write(SVG_SUFFIX);
    }

    function initializeImprint(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) external initializer initializerERC721A {
        __Imprint_init(name, symbol, allowedSeaDrop);
    }

    /**
     * @notice A token can only be burned by the set burn address.
     */
    error BurnIncorrectSender();

    function setBurnAddress(address newBurnAddress) external onlyOwner {
        ImprintStorage.layout().burnAddress = newBurnAddress;
    }

    function getBurnAddress() public view returns (address) {
        return ImprintStorage.layout().burnAddress;
    }

    /**
     * @notice Destroys `tokenId`, only callable by the set burn address.
     *
     * @param tokenId The token id to burn.
     */
    function burn(uint256 tokenId) external override {
        if (msg.sender != ImprintStorage.layout().burnAddress) {
            revert BurnIncorrectSender();
        }

        _burn(tokenId);
    }
}
