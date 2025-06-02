// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";
import { Base64 } from "openzeppelin-contracts/utils/Base64.sol";
import { IImprintDescriptor } from "./interfaces/IImprintDescriptor.sol";

struct TokenMeta {
    uint64 editionNo;
    uint16 localIndex;
    string model;
    string subjectName;
}

interface IImprint {
    function descPtr(uint256 tokenId) external view returns (address);

    function getTokenMeta(uint256 tokenId)
        external
        view
        returns (TokenMeta memory);
}

contract ImprintDescriptor is IImprintDescriptor {
    using Strings for uint256;

    address public immutable imprint;
    address public immutable svgPrefixPtr;
    address public immutable svgSuffixPtr;

    // Storage mapping for descPtr that Imprint can write to
    mapping(uint256 => address) public descPtr;

    constructor(address _imprint) {
        require(_imprint != address(0), "zero address");
        imprint = _imprint;

        // Initialize SVG templates
        svgPrefixPtr = SSTORE2.write(
            '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">'
            '<rect width="100%" height="100%" fill="black"/>'
            '<foreignObject x="10" y="10" width="330" height="330">'
            '<div xmlns="http://www.w3.org/1999/xhtml" style="color:white;font:20px/1.4 Courier New,monospace;overflow-wrap:anywhere;">'
        );
        svgSuffixPtr = SSTORE2.write("</div></foreignObject></svg>");
    }

    /// @notice Allows the Imprint contract to set descPtr for a token
    /// @param tokenId The token ID
    /// @param ptr The SSTORE2 pointer address for the description
    function setDescPtr(uint256 tokenId, address ptr) external {
        require(msg.sender == imprint, "only imprint");
        descPtr[tokenId] = ptr;
    }

    function tokenImage(uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        IImprint imp = IImprint(imprint);
        address ptr = imp.descPtr(tokenId);
        require(ptr != address(0), "desc missing");

        // Build SVG
        bytes memory svg = abi.encodePacked(
            SSTORE2.read(svgPrefixPtr),
            SSTORE2.read(ptr),
            SSTORE2.read(svgSuffixPtr)
        );

        return
            string(
                abi.encodePacked(
                    "data:image/svg+xml;base64,",
                    Base64.encode(svg)
                )
            );
    }

    function tokenURI(uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        IImprint imp = IImprint(imprint);
        address ptr = imp.descPtr(tokenId);
        require(ptr != address(0), "desc missing");

        TokenMeta memory tokenMeta = imp.getTokenMeta(tokenId);
        require(bytes(tokenMeta.model).length != 0, "meta missing");

        // Build SVG
        bytes memory svg = abi.encodePacked(
            SSTORE2.read(svgPrefixPtr),
            SSTORE2.read(ptr),
            SSTORE2.read(svgSuffixPtr)
        );

        string memory svgB64 = Base64.encode(svg);

        // Build JSON metadata
        bytes memory json = abi.encodePacked(
            '{"name":"Imprint #',
            tokenId.toString(),
            " - ",
            tokenMeta.subjectName,
            " (",
            tokenMeta.model,
            ')"',
            ',"attributes":['
            '{"trait_type":"Edition","value":"',
            uint256(tokenMeta.editionNo).toString(),
            '"},'
            '{"trait_type":"Local Index","value":"',
            uint256(tokenMeta.localIndex).toString(),
            '"},'
            '{"trait_type":"Model","value":"',
            tokenMeta.model,
            '"},'
            '{"trait_type":"Subject","value":"',
            tokenMeta.subjectName,
            '"}'
            '],"image":"data:image/svg+xml;base64,',
            svgB64,
            '"}'
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(json)
                )
            );
    }
}
