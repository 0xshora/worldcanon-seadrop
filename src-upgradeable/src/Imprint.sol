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

        /* --- Sale --- */
        uint64  activeEdition;       // 現在販売中の Edition
        uint256 activeCursor;        // その Edition 内で次に配布する seedId
        mapping(uint64 => uint256) firstSeedId;   // editionNo -> 先頭 seedId
        mapping(uint64 => uint256) lastSeedId;    // editionNo -> 末尾 seedId
        mapping(uint64 => mapping(uint16 => bool)) localIndexTaken;

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

/// @dev owner が Seed を一括登録するときに使う入力フォーマット
struct SeedInput {
    uint64  editionNo;      // 紐づく Edition
    uint16  localIndex;     // Edition 内の連番
    uint256 subjectId;      // Subject tokenId（まだ使わなければ 0 でも可）
    string  subjectName;    // 表示用名
    bytes   desc;           // SVG 本文（UTF-8）最大 280Byte 推奨
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
    event SeedsAdded(uint64 indexed editionNo, uint256 count);
    event ImprintClaimed(uint256 indexed seedId, uint256 indexed tokenId, address indexed to);
    event ActiveEditionChanged(uint64 indexed newEdition);

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

    function addSeeds(SeedInput[] calldata inputs) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint256 n = inputs.length;
        require(n > 0, "empty");

        uint64 batchEdition = inputs[0].editionNo;

        for (uint256 i; i < n; ++i) {
            SeedInput calldata sIn = inputs[i];
            require(sIn.editionNo == batchEdition, "mixed edition");
            require(sIn.desc.length != 0, "desc empty");

            ImprintStorage.EditionHeader storage hdr =
                st.editionHeaders[sIn.editionNo];
            require(hdr.editionNo != 0,  "edition missing");
            require(!hdr.isSealed,       "edition sealed");

            require(
                !st.localIndexTaken[sIn.editionNo][sIn.localIndex],
                "dup localIdx"
            );
            st.localIndexTaken[sIn.editionNo][sIn.localIndex] = true;

            uint256 newId = ++st.nextSeedId;
            st.seeds[newId] = ImprintStorage.ImprintSeed({
                editionNo:   sIn.editionNo,
                localIndex:  sIn.localIndex,
                subjectId:   sIn.subjectId,
                subjectName: sIn.subjectName,
                descPtr:     SSTORE2.write(sIn.desc),
                claimed:     false
            });

            if (st.firstSeedId[sIn.editionNo] == 0) {
                st.firstSeedId[sIn.editionNo] = newId;
            }
            st.lastSeedId[sIn.editionNo] = newId;
        }

        emit SeedsAdded(batchEdition, n);
    }


    // ──────────────────────────────────────────────
    //  2) Edition 切替
    // ──────────────────────────────────────────────
    function setActiveEdition(uint64 editionNo) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        require(h.editionNo != 0,  "edition missing");
        require(h.isSealed,        "edition not sealed");
        require(st.firstSeedId[editionNo] != 0, "no seeds");

        st.activeEdition = editionNo;
        // 次 mint する seed を先頭にリセット
        st.activeCursor  = st.firstSeedId[editionNo];
        emit ActiveEditionChanged(editionNo);
    }

    // ──────────────────────────────────────────────
    //  3) SeaDrop からの Mint → Seed Claim
    // ──────────────────────────────────────────────
    function mintSeaDrop(address to, uint256 quantity)
        external
        override
        nonReentrant
    {
        _onlyAllowedSeaDrop(msg.sender);

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint64 ed = st.activeEdition;
        require(ed != 0, "no active edition");

        uint256 cursor = st.activeCursor;
        uint256 last   = st.lastSeedId[ed];
        require(cursor != 0 && cursor + quantity - 1 <= last, "sold out");

        uint256 firstTokenId = _nextTokenId();

        // Extra safety check to ensure the max supply is not exceeded.
        if (_totalMinted() + quantity > maxSupply()) {
            revert MintQuantityExceedsMaxSupply(
                _totalMinted() + quantity,
                maxSupply()
            );
        }

        _safeMint(to, quantity);                        // ERC721A が連番で発行

        for (uint256 i; i < quantity; ++i) {
            uint256 seedId  = cursor + i;
            uint256 tokenId = firstTokenId + i;

            ImprintStorage.ImprintSeed storage s = st.seeds[seedId];
            s.claimed = true;

            // 書き込み
            st.descPtr[tokenId] = s.descPtr;
            st.meta[tokenId] = ImprintStorage.TokenMeta({
                editionNo:   s.editionNo,
                localIndex:  s.localIndex,
                model:       st.editionHeaders[ed].model,
                subjectName: s.subjectName
            });

            emit ImprintClaimed(seedId, tokenId, to);
        }

        st.activeCursor = cursor + quantity;            // 次の Seed へ前進
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
