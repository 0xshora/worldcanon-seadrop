// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDropUpgradeable } from "./ERC721SeaDropUpgradeable.sol";
import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";
import {Base64}  from "openzeppelin-contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// ──────────────────────────────────────────────────────────────
///  ImprintStorage  ── World Canon / Imprint  固定ストレージ
/// ──────────────────────────────────────────────────────────────
library ImprintStorage {
    /*═════════ ① 不変データ構造 ═════════*/

    /// Edition 毎のヘッダー
    struct EditionHeader {
        uint64  editionNo;   // 連番（＝キー）
        string  model;       // 例 "GPT-4o"
        uint64  timestamp;   // block.timestamp (UTC 秒)
        bool    isSealed;      // true なら Seed 追加不可
    }

    /// SeaDrop ミント前にプレ登録する “Seed”
    struct ImprintSeed {
        uint64   editionNo;      // 紐づく Edition
        uint16   localIndex;     // Edition 内 index
        uint256  subjectId;      // Subject tokenId
        string   subjectName;    // Subject 名
        address  descPtr;        // SSTORE2 ポインタ
        bool     claimed;        // mint 済みか
    }

    /// Mint 後、Subject 側から呼ばれるときに使う最終メタ
    struct TokenMeta {
        uint64  editionNo;
        uint16  localIndex;      // Edition 内 index
        string  model;
        string  subjectName;
    }

    /*═════════ ② Diamond-Layout ═════════*/

    struct Layout {
        /* --- Finalised Imprint (tokenId 同値) --- */
        mapping(uint256 => address)     descPtr;   // slot offset 0
        mapping(uint256 => TokenMeta)   meta;      // slot offset 1

        /* --- Edition & Seed --- */
        mapping(uint64  => EditionHeader) editionHeaders;   // slot offset 2
        mapping(uint256 => ImprintSeed)   seeds;            // slot offset 3
        uint256  nextSeedId;                                // slot offset 4

        /* --- Globals --- */
        address  worldCanon;   // Subject コントラクト (set once)
        uint64   maxSupply;    // 0 = unlimited
    }

    /*═════════ ③ 取得ヘルパ ═════════*/

    bytes32 internal constant STORAGE_SLOT =
        keccak256("worldcanon.imprint.storage.v0");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
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

    /* ──────────────── events ──────────────── */
    event EditionCreated(uint64 indexed editionNo, string model, uint64 timestamp);
    event EditionSealed(uint64 indexed editionNo);

    /* ──────────────── init ──────────────── */
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

    /*═══════════════════════  Edition  API  ══════════════════════*/
    /// @notice 新しい Edition を作成する。owner 専用。
    function createEdition(uint64 editionNo, string calldata model)
        external
        onlyOwner
    {
        require(editionNo != 0,               "editionNo=0");
        require(bytes(model).length != 0,     "model empty");

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        // 未使用かチェック（editionNo は一意）
        require(st.editionHeaders[editionNo].editionNo == 0, "edition exists");
        st.editionHeaders[editionNo] = ImprintStorage.EditionHeader({
            editionNo:  editionNo,
            model:      model,
            timestamp:  uint64(block.timestamp),
            isSealed:   false
        });
        emit EditionCreated(editionNo, model, uint64(block.timestamp));
    }

    /// @notice 既存 Edition を封鎖（Seed 追加を禁止）する。owner 専用。
    function sealEdition(uint64 editionNo) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        require(h.editionNo != 0,   "unknown edition");
        require(!h.isSealed,        "already sealed");
        h.isSealed = true;
        emit EditionSealed(editionNo);
    }

    /* ───────── setter(admin only, deprecated) ───────── */
    function _adminSetMeta(
        uint256 tokenId,
        uint64  editionNo,
        uint16  localIndex,
        string calldata model,
        string calldata subjectName
    ) external onlyOwner {
        require(_exists(tokenId), "nonexistent");
        ImprintStorage.layout().meta[tokenId] =
            ImprintStorage.TokenMeta(editionNo, localIndex, model, subjectName);
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
                '{"trait_type":"Local Index","value":"', Strings.toString(m.localIndex), '"},'
                '{"trait_type":"Model","value":"', m.model, '"},'
                '{"trait_type":"Subject","value":"', m.subjectName, '"}'
            '],"image":"data:image/svg+xml;base64,', svgB64, '"}'
        );
        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(json))
        );
    }

    /*─────────────── Edition header view ───────────────*/
    function getEditionHeader(uint64 editionNo)
        external
        view
        returns (ImprintStorage.EditionHeader memory)
    {
        return ImprintStorage.layout().editionHeaders[editionNo];
    }

    uint256[50] private __gap;

}
