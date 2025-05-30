// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDropUpgradeable } from "./ERC721SeaDropUpgradeable.sol";
import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";
import {INonFungibleSeaDropTokenUpgradeable} from "./interfaces/INonFungibleSeaDropTokenUpgradeable.sol";
import {ISeaDropTokenContractMetadataUpgradeable} from "./interfaces/ISeaDropTokenContractMetadataUpgradeable.sol";
import { IImprintDescriptor } from "./interfaces/IImprintDescriptor.sol";

/// Interface for Subject contract
interface ISubject {
    function syncFromImprint(string calldata subjectName, uint256 imprintId, uint64 ts) external;
}

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
        /* --- Finalized Imprint (tokenId 同値) --- */
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
        bool     mintPaused;   // Mint一時停止フラグ
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

// Custom errors - shortened for binary size optimization
error ZA();  // ZeroAddress
error IE();  // InvalidEditionNo
error EM();  // EmptyModel
error EE();  // EditionExists
error UE();  // UnknownEdition
error AS();  // AlreadySealed
error EI();  // EmptyInput
error ME();  // MixedEdition
error ED();  // EmptyDesc
error EMi(); // EditionMissing
error EAS(); // EditionAlreadySealed
error DL();  // DuplicateLocalIdx
error ENS(); // EditionNotSealed
error NS();  // NoSeeds
error MP();  // MintingPaused
error NAE(); // NoActiveEdition
error SO();  // SoldOut
error TN();  // TokenNonexistent
error DU();  // DescriptorUnset
error DF();  // DescriptorFail
error WAS(); // WorldCanonAlreadySet

/*
 * @notice This contract uses ERC721SeaDrop,
 *         an ERC721A token contract that is compatible with SeaDrop.
 *         The set burn address is the only sender that can burn tokens.
 */
contract Imprint is ERC721SeaDropUpgradeable {
    using ImprintStorage for ImprintStorage.Layout;


    event EditionCreated(uint64 indexed editionNo, string model, uint64 timestamp);
    event EditionSealed(uint64 indexed editionNo);
    event ActiveEditionChanged(uint64 indexed newEdition);
    event WorldCanonSet(address indexed worldCanon);

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
        if (initialOwner == address(0)) revert ZA();
        _transferOwnership(initialOwner);
    }

    function createEdition(uint64 editionNo, string calldata model)
        external
        onlyOwner
    {
        if (editionNo == 0) revert IE();
        if (bytes(model).length == 0) revert EM();

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        // 未使用かチェック（editionNo は一意）
        if (st.editionHeaders[editionNo].editionNo != 0) revert EE();
        st.editionHeaders[editionNo] = ImprintStorage.EditionHeader({
            editionNo:  editionNo,
            model:      model,
            timestamp:  uint64(block.timestamp),
            isSealed:   false
        });
        emit EditionCreated(editionNo, model, uint64(block.timestamp));
    }

    function sealEdition(uint64 editionNo) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UE();
        if (h.isSealed) revert AS();
        h.isSealed = true;
        emit EditionSealed(editionNo);
    }

    function addSeeds(SeedInput[] calldata inputs) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint256 n = inputs.length;
        if (n == 0) revert EI();

        uint64 batchEdition = inputs[0].editionNo;
        ImprintStorage.EditionHeader storage hdr = st.editionHeaders[batchEdition];
        if (hdr.editionNo == 0) revert EMi();
        if (hdr.isSealed) revert EAS();

        unchecked {
            for (uint256 i; i < n; ++i) {
                SeedInput calldata sIn = inputs[i];
                if (sIn.editionNo != batchEdition) revert ME();
                if (sIn.desc.length == 0) revert ED();
                if (st.localIndexTaken[batchEdition][sIn.localIndex]) revert DL();
                
                st.localIndexTaken[batchEdition][sIn.localIndex] = true;
                uint256 newId = ++st.nextSeedId;
                st.seeds[newId] = ImprintStorage.ImprintSeed({
                    editionNo:   batchEdition,
                    localIndex:  sIn.localIndex,
                    subjectId:   sIn.subjectId,
                    subjectName: sIn.subjectName,
                    descPtr:     SSTORE2.write(sIn.desc),
                    claimed:     false
                });

                if (st.firstSeedId[batchEdition] == 0) st.firstSeedId[batchEdition] = newId;
                st.lastSeedId[batchEdition] = newId;
            }
        }
    }
    function setActiveEdition(uint64 editionNo) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        
        if (editionNo == 0) {
            st.activeEdition = 0;
            st.activeCursor = 0;
            emit ActiveEditionChanged(0);
            return;
        }

        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UE();
        if (!h.isSealed) revert ENS();
        if (st.firstSeedId[editionNo] == 0) revert NS();

        st.activeEdition = editionNo;
        st.activeCursor = st.firstSeedId[editionNo];
        emit ActiveEditionChanged(editionNo);
    }
    function mintSeaDrop(address to, uint256 quantity)
        external
        override
        nonReentrant
    {
        _onlyAllowedSeaDrop(msg.sender);
        
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.mintPaused) revert MP();

        uint64 ed = st.activeEdition;
        if (ed == 0) revert NAE();

        uint256 cursor = st.activeCursor;
        uint256 last   = st.lastSeedId[ed];
        if (cursor == 0 || cursor + quantity - 1 > last) revert SO();

        uint256 firstTokenId = _nextTokenId();

        string memory model = st.editionHeaders[ed].model;
        unchecked {
            for (uint256 i; i < quantity; ++i) {
                uint256 seedId  = cursor + i;
                uint256 tokenId = firstTokenId + i;
                ImprintStorage.ImprintSeed storage s = st.seeds[seedId];
                s.claimed = true;
                st.descPtr[tokenId] = s.descPtr;
                st.meta[tokenId] = ImprintStorage.TokenMeta({
                    editionNo:   ed,
                    localIndex:  s.localIndex,
                    model:       model,
                    subjectName: s.subjectName
                });
            }
        }

        st.activeCursor = cursor + quantity;
        _safeMint(to, quantity);

        if (st.worldCanon != address(0)) {
            ISubject wc = ISubject(st.worldCanon);
            unchecked {
                for (uint256 i; i < quantity; ++i) {
                    uint256 tokenId = firstTokenId + i;
                    ImprintStorage.TokenMeta memory m = st.meta[tokenId];
                    wc.syncFromImprint(m.subjectName, tokenId, uint64(block.timestamp));
                }
            }
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TN();
        if (descriptor == address(0)) revert DU();
        (bool ok, bytes memory data) = descriptor.staticcall(abi.encodeWithSelector(IImprintDescriptor.tokenURI.selector, tokenId));
        if (!ok) revert DF();
        return abi.decode(data, (string));
    }

    function setWorldCanon(address worldCanon) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.worldCanon != address(0)) revert WAS();
        if (worldCanon == address(0)) revert ZA();
        st.worldCanon = worldCanon;
        emit WorldCanonSet(worldCanon);
    }

    function setMintPaused(bool paused) external onlyOwner {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        st.mintPaused = paused;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721SeaDropUpgradeable) returns (bool) {
        return interfaceId == type(INonFungibleSeaDropTokenUpgradeable).interfaceId ||
               interfaceId == type(ISeaDropTokenContractMetadataUpgradeable).interfaceId ||
               super.supportsInterface(interfaceId);
    }

    address public descriptor;
    function setDescriptor(address _descriptor) external onlyOwner {
        if (_descriptor == address(0)) revert ZA();
        descriptor = _descriptor;
    }


    uint256[51] private __gap;

}
