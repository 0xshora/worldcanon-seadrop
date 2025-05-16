// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDropUpgradeable } from "./ERC721SeaDropUpgradeable.sol";
import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";
import {Base64}  from "openzeppelin-contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

library ImprintStorage {
    struct TokenMeta {
        uint64  editionNo;
        string  model;        // 例 "GPT-4o"
        string  subjectName;  // 例 "Happiness"
    }

    struct Layout {
        mapping(uint256 => address)  descPtr; // tokenId → SSTORE2 pointer
        mapping(uint256 => TokenMeta) meta;   // tokenId → metadata
    }
    function layout() internal pure returns (Layout storage l) {
        bytes32 s = keccak256("worldcanon.imprint.storage.v0");
        assembly { l.slot := s }
    }
}


/*
 * @notice This contract uses ERC721SeaDrop,
 *         an ERC721A token contract that is compatible with SeaDrop.
 *         The set burn address is the only sender that can burn tokens.
 */
contract Imprint is ERC721SeaDropUpgradeable {
    using ImprintStorage for ImprintStorage.Layout;

    // // SVG container template parts
    // bytes private constant SVG_PREFIX = abi.encodePacked(
    //     "<svg xmlns='http://www.w3.org/2000/svg' width='350' height='350'>",
    //     "<rect width='100%' height='100%' fill='black'/>",
    //     "<foreignObject x='10' y='10' width='330' height='330'>",
    //     "<div xmlns='http://www.w3.org/1999/xhtml' style='color:white;font:20px/1.4 Courier New,monospace;overflow-wrap:anywhere;'>"
    // );
    // bytes private constant SVG_SUFFIX = "</div></foreignObject></svg>";

    address public svgPrefixPtr;
    address public svgSuffixPtr;

    function __Imprint_init(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) internal onlyInitializing {
        // Initialize ERC721SeaDrop with name, symbol, and allowed SeaDrop
        __ERC721SeaDrop_init(name, symbol, allowedSeaDrop);

        // Initialize SVG pointers
        svgPrefixPtr = SSTORE2.write(
            '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">'
            '<rect width="100%" height="100%" fill="black"/>'
            '<foreignObject x="10" y="10" width="330" height="330">'
            '<div xmlns="http://www.w3.org/1999/xhtml" style="color:white;font:20px/1.4 Courier New,monospace;overflow-wrap:anywhere;">'
        );
        svgSuffixPtr = SSTORE2.write('</div></foreignObject></svg>');
    }

    function initializeImprint(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        address initialOwner
    ) external initializer initializerERC721A {
        __Imprint_init(name, symbol, allowedSeaDrop);
        require(initialOwner != address(0), "owner = zero address");
        _transferOwnership(initialOwner);   // OwnableUpgradeable
    }

    /* ───────── setter(admin only, deprecated) ───────── */
    function _adminSetMeta(
        uint256 tokenId,
        uint64  editionNo,
        string calldata model,
        string calldata subjectName
    ) external onlyOwner {
        require(_exists(tokenId), "nonexistent");
        ImprintStorage.layout().meta[tokenId] =
            ImprintStorage.TokenMeta(editionNo, model, subjectName);
    }

    /*═══════════════════════ Metadata helpers ═══════════════════════*/
    function _buildSVG(address ptr) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                SSTORE2.read(svgPrefixPtr),
                SSTORE2.read(ptr),
                SSTORE2.read(svgSuffixPtr)
            )
        );
    }

    /// @notice Subject コントラクトが呼ぶプレーン SVG Data-URI
    function tokenImage(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "nonexistent");
        address ptr = ImprintStorage.layout().descPtr[tokenId];
        require(ptr != address(0), "desc missing");
        return string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(_buildSVG(ptr)))
            )
        );
    }

    /// @notice Marketplace 表示用 JSON メタデータ
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "nonexistent");

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        address ptr = st.descPtr[tokenId];
        require(ptr != address(0), "desc missing");

        ImprintStorage.TokenMeta memory m = st.meta[tokenId];
        require(bytes(m.model).length != 0, "meta missing");

        string memory svgB64 = Base64.encode(bytes(_buildSVG(ptr)));

        bytes memory json = abi.encodePacked(
            '{"name":"Imprint #', Strings.toString(tokenId), ' - ', m.subjectName,
            ' (', m.model, ')"',
            ',"attributes":['
                '{"trait_type":"Edition","value":"', Strings.toString(m.editionNo), '"},'
                '{"trait_type":"Model","value":"', m.model, '"},'
                '{"trait_type":"Subject","value":"', m.subjectName, '"}'
            '],"image":"data:image/svg+xml;base64,', svgB64, '"}'
        );
        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(json))
        );
    }

    uint256[50] private __gap;

}
