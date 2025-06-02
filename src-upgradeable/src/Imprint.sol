// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDropUpgradeable } from "./ERC721SeaDropUpgradeable.sol";
import {INonFungibleSeaDropTokenUpgradeable} from "./interfaces/INonFungibleSeaDropTokenUpgradeable.sol";
import {ISeaDropTokenContractMetadataUpgradeable} from "./interfaces/ISeaDropTokenContractMetadataUpgradeable.sol";
import { IImprintDescriptor } from "./interfaces/IImprintDescriptor.sol";
import { 
    ImprintLib, 
    SeedInput, 
    ImprintStorage, 
    ZeroAddress,
    MintingPaused,
    NoActiveEdition,
    SoldOut,
    TokenNonexistent,
    DescriptorUnset,
    DescriptorFail,
    WorldCanonAlreadySet
} from "./ImprintLib.sol";

/*
 * @notice This contract uses ERC721SeaDrop,
 *         an ERC721A token contract that is compatible with SeaDrop.
 *         The set burn address is the only sender that can burn tokens.
 */
contract Imprint is ERC721SeaDropUpgradeable {
    using ImprintStorage for ImprintStorage.Layout;

    /* ──────────────── init ──────────────── */
    function __Imprint_init(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) internal onlyInitializing {
        __ERC721SeaDrop_init(name, symbol, allowedSeaDrop);
    }

    function initializeImprint(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address initialOwner
    ) external initializer initializerERC721A {
        __Imprint_init(name, symbol, allowedSeaDrop);
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);
    }

    /*═══════════════════════  Edition  API  ══════════════════════*/
    function createEdition(uint64 editionNo, string calldata model) external onlyOwner {
        ImprintLib.createEditionWithEvent(editionNo, model);
    }

    function sealEdition(uint64 editionNo) external onlyOwner {
        ImprintLib.sealEditionWithEvent(editionNo);
    }

    function addSeeds(SeedInput[] calldata inputs) external onlyOwner {
        ImprintLib.addSeeds(inputs);
    }

    function setActiveEdition(uint64 editionNo) external onlyOwner {
        ImprintLib.setActiveEditionWithEvent(editionNo);
    }

    function mintSeaDrop(address to, uint256 quantity) external override nonReentrant {
        _onlyAllowedSeaDrop(msg.sender);
        uint256 firstTokenId = _nextTokenId();
        ImprintLib.processMint(to, quantity, firstTokenId);
        _safeMint(to, quantity);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenNonexistent();
        if (descriptor == address(0)) revert DescriptorUnset();
        
        (bool ok, bytes memory data) = descriptor.staticcall(
            abi.encodeWithSelector(IImprintDescriptor.tokenURI.selector, tokenId)
        );
        if (!ok) revert DescriptorFail();
        return abi.decode(data, (string));
    }

    function setWorldCanon(address worldCanon) external onlyOwner {
        ImprintLib.setWorldCanonWithEvent(worldCanon);
    }

    function setMintPaused(bool paused) external onlyOwner {
        ImprintLib.setMintPaused(paused);
    }

    function supportsInterface(bytes4 interfaceId) 
        public view virtual override(ERC721SeaDropUpgradeable) returns (bool) 
    {
        return 
            interfaceId == type(INonFungibleSeaDropTokenUpgradeable).interfaceId ||
            interfaceId == type(ISeaDropTokenContractMetadataUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    address public descriptor;

    function setDescriptor(address _descriptor) external onlyOwner {
        if (_descriptor == address(0)) revert ZeroAddress();
        descriptor = _descriptor;
    }

    // Delegate to ImprintLib
    function getEditionHeader(uint64 editionNo) external view returns (ImprintStorage.EditionHeader memory) {
        return ImprintLib.getEditionHeader(editionNo);
    }
    function getSeed(uint256 seedId) external view returns (ImprintStorage.ImprintSeed memory) {
        return ImprintLib.getSeed(seedId);
    }
    function getTokenMeta(uint256 tokenId) external view returns (ImprintStorage.TokenMeta memory) {
        return ImprintLib.getTokenMeta(tokenId);
    }
    function descPtr(uint256 tokenId) external view returns (address) {
        return ImprintLib.getDescPtr(tokenId);
    }
    function remainingInEdition(uint64 editionNo) external view returns (uint256) {
        return ImprintLib.getRemainingInEdition(editionNo);
    }
    function getWorldCanon() external view returns (address) {
        return ImprintLib.getWorldCanon();
    }
    function isMintPaused() external view returns (bool) {
        return ImprintLib.isMintPaused();
    }
    function editionSize(uint64 ed) external view returns (uint256) {
        return ImprintLib.getEditionSize(ed);
    }


    uint256[50] private __gap;
}
