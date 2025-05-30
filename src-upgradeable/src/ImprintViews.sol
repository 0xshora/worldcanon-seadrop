// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ImprintStorage } from "./Imprint.sol";

/**
 * @title ImprintViews
 * @notice Thin wrapper that calls Imprint's view functions via staticcall
 */
contract ImprintViews {
    address public immutable imprint;

    constructor(address _imprint) {
        require(_imprint != address(0), "zero address");
        imprint = _imprint;
    }

    function getEditionHeader(uint64 editionNo) external view returns (ImprintStorage.EditionHeader memory) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0x195b2ea7, editionNo) // getEditionHeader selector
        );
        require(success, "call failed");
        return abi.decode(data, (ImprintStorage.EditionHeader));
    }

    function getSeed(uint256 seedId) external view returns (ImprintStorage.ImprintSeed memory) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0xe0d4ea37, seedId) // getSeed selector
        );
        require(success, "call failed");
        return abi.decode(data, (ImprintStorage.ImprintSeed));
    }

    function getTokenMeta(uint256 tokenId) external view returns (ImprintStorage.TokenMeta memory) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0xb40e5570, tokenId) // getTokenMeta selector
        );
        require(success, "call failed");
        return abi.decode(data, (ImprintStorage.TokenMeta));
    }

    function remainingInEdition(uint64 editionNo) external view returns (uint256) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0x03e0c537, editionNo) // remainingInEdition selector
        );
        require(success, "call failed");
        return abi.decode(data, (uint256));
    }

    // Pass-through functions that were already on Imprint
    function getWorldCanon() external view returns (address) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0xbf45a6d5) // getWorldCanon selector
        );
        require(success, "call failed");
        return abi.decode(data, (address));
    }

    function isMintPaused() external view returns (bool) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0x15839b30) // isMintPaused selector
        );
        require(success, "call failed");
        return abi.decode(data, (bool));
    }

    function editionSize(uint64 ed) external view returns (uint256) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0xfe33b53c, ed) // editionSize selector
        );
        require(success, "call failed");
        return abi.decode(data, (uint256));
    }

    function descPtr(uint256 tokenId) external view returns (address) {
        (bool success, bytes memory data) = imprint.staticcall(
            abi.encodeWithSelector(0x9d02848b, tokenId) // descPtr selector
        );
        require(success, "call failed");
        return abi.decode(data, (address));
    }

}