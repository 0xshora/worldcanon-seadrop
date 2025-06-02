// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SSTORE2 } from "../lib-upgradeable/solmate/src/utils/SSTORE2.sol";

/// @dev owner が Seed を一括登録するときに使う入力フォーマット
struct SeedInput {
    uint64 editionNo; // 紐づく Edition
    uint16 localIndex; // Edition 内の連番
    uint256 subjectId; // Subject tokenId（まだ使わなければ 0 でも可）
    string subjectName; // 表示用名
    bytes desc; // SVG 本文（UTF-8）最大 280Byte 推奨
}

/// ──────────────────────────────────────────────────────────────
///  ImprintStorage  ── World Canon / Imprint  固定ストレージ
/// ──────────────────────────────────────────────────────────────
library ImprintStorage {
    /*═════════ ① 不変データ構造 ═════════*/

    /// Edition 毎のヘッダー
    struct EditionHeader {
        uint64 editionNo; // 連番（＝キー）
        string model; // 例 "GPT-4o"
        uint64 timestamp; // block.timestamp (UTC 秒)
        bool isSealed; // true なら Seed 追加不可
    }

    /// SeaDrop ミント前にプレ登録する "Seed"
    struct ImprintSeed {
        uint64 editionNo; // 紐づく Edition
        uint16 localIndex; // Edition 内 index
        uint256 subjectId; // Subject tokenId
        string subjectName; // Subject 名
        address descPtr; // SSTORE2 ポインタ
        bool claimed; // mint 済みか
    }

    /// Mint 後、Subject 側から呼ばれるときに使う最終メタ
    struct TokenMeta {
        uint64 editionNo;
        uint16 localIndex; // Edition 内 index
        string model;
        string subjectName;
    }

    /*═════════ ② Diamond-Layout ═════════*/

    struct Layout {
        /* --- Finalized Imprint (tokenId 同値) --- */
        mapping(uint256 => address) descPtr; // slot offset 0
        mapping(uint256 => TokenMeta) meta; // slot offset 1
        /* --- Edition & Seed --- */
        mapping(uint64 => EditionHeader) editionHeaders; // slot offset 2
        mapping(uint256 => ImprintSeed) seeds; // slot offset 3
        uint256 nextSeedId; // slot offset 4
        /* --- Sale --- */
        uint64 activeEdition; // 現在販売中の Edition
        uint256 activeCursor; // その Edition 内で次に配布する seedId
        mapping(uint64 => uint256) firstSeedId; // editionNo -> 先頭 seedId
        mapping(uint64 => uint256) lastSeedId; // editionNo -> 末尾 seedId
        mapping(uint64 => mapping(uint16 => bool)) localIndexTaken;
        /* --- Globals --- */
        address worldCanon; // Subject コントラクト (set once)
        bool mintPaused; // Mint一時停止フラグ
    }

    /*═════════ ③ 取得ヘルパ ═════════*/

    bytes32 internal constant STORAGE_SLOT =
        keccak256("worldcanon.imprint.storage.v0");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

// Custom errors for gas optimization
error ZeroAddress();
error InvalidEditionNo();
error EmptyModel();
error EditionExists();
error UnknownEdition();
error AlreadySealed();
error EmptyInput();
error MixedEdition();
error EmptyDesc();
error EditionMissing();
error EditionAlreadySealed();
error DuplicateLocalIdx();
error EditionNotSealed();
error NoSeeds();
error MintingPaused();
error NoActiveEdition();
error SoldOut();
error TokenNonexistent();
error DescriptorUnset();
error DescriptorFail();
error WorldCanonAlreadySet();

library ImprintLib {
    using ImprintStorage for ImprintStorage.Layout;

    event EditionCreated(
        uint64 indexed editionNo,
        string model,
        uint64 timestamp
    );
    event EditionSealed(uint64 indexed editionNo);
    event ActiveEditionChanged(uint64 indexed newEdition);
    event WorldCanonSet(address indexed worldCanon);

    function createEditionWithEvent(uint64 editionNo, string calldata model)
        external
    {
        if (editionNo == 0) revert InvalidEditionNo();
        if (bytes(model).length == 0) revert EmptyModel();

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.editionHeaders[editionNo].editionNo != 0) revert EditionExists();

        uint64 timestamp = uint64(block.timestamp);
        st.editionHeaders[editionNo] = ImprintStorage.EditionHeader({
            editionNo: editionNo,
            model: model,
            timestamp: timestamp,
            isSealed: false
        });

        emit EditionCreated(editionNo, model, timestamp);
    }

    function sealEditionWithEvent(uint64 editionNo) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UnknownEdition();
        if (h.isSealed) revert AlreadySealed();
        h.isSealed = true;

        emit EditionSealed(editionNo);
    }

    function setActiveEditionWithEvent(uint64 editionNo) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();

        if (editionNo == 0) {
            st.activeEdition = 0;
            st.activeCursor = 0;
            emit ActiveEditionChanged(0);
            return;
        }

        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UnknownEdition();
        if (!h.isSealed) revert EditionNotSealed();
        if (st.firstSeedId[editionNo] == 0) revert NoSeeds();

        st.activeEdition = editionNo;
        st.activeCursor = st.firstSeedId[editionNo];

        emit ActiveEditionChanged(editionNo);
    }

    function setWorldCanonWithEvent(address worldCanon) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.worldCanon != address(0)) revert WorldCanonAlreadySet();
        if (worldCanon == address(0)) revert ZeroAddress();
        st.worldCanon = worldCanon;

        emit WorldCanonSet(worldCanon);
    }

    function processMint(
        address, /*to*/
        uint256 quantity,
        uint256 firstTokenId
    ) external returns (uint256) {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.mintPaused) revert MintingPaused();

        uint64 ed = st.activeEdition;
        if (ed == 0) revert NoActiveEdition();

        uint256 cursor = st.activeCursor;
        uint256 last = st.lastSeedId[ed];
        if (cursor == 0 || cursor + quantity - 1 > last) revert SoldOut();

        string memory model = st.editionHeaders[ed].model;
        address worldCanon = st.worldCanon;

        unchecked {
            for (uint256 i; i < quantity; ++i) {
                uint256 seedId = cursor + i;
                uint256 tokenId = firstTokenId + i;
                ImprintStorage.ImprintSeed storage s = st.seeds[seedId];
                s.claimed = true;
                st.descPtr[tokenId] = s.descPtr;
                st.meta[tokenId] = ImprintStorage.TokenMeta({
                    editionNo: ed,
                    localIndex: s.localIndex,
                    model: model,
                    subjectName: s.subjectName
                });

                // Sync with Subject directly here
                if (worldCanon != address(0)) {
                    (bool success, ) = worldCanon.call(
                        abi.encodeWithSignature(
                            "syncFromImprint(string,uint256,uint64)",
                            s.subjectName,
                            tokenId,
                            uint64(block.timestamp)
                        )
                    );
                    // Ignore failures to prevent mint blocking
                    success;
                }
            }
        }

        st.activeCursor = cursor + quantity;

        return firstTokenId;
    }

    function createEdition(uint64 editionNo, string calldata model) external {
        if (editionNo == 0) revert InvalidEditionNo();
        if (bytes(model).length == 0) revert EmptyModel();

        ImprintStorage.Layout storage st = ImprintStorage.layout();
        if (st.editionHeaders[editionNo].editionNo != 0) revert EditionExists();
        st.editionHeaders[editionNo] = ImprintStorage.EditionHeader({
            editionNo: editionNo,
            model: model,
            timestamp: uint64(block.timestamp),
            isSealed: false
        });
    }

    function sealEdition(uint64 editionNo) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UnknownEdition();
        if (h.isSealed) revert AlreadySealed();
        if (st.firstSeedId[editionNo] == 0) revert NoSeeds();
        h.isSealed = true;
    }

    function addSeeds(SeedInput[] calldata inputs) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint256 n = inputs.length;
        if (n == 0) revert EmptyInput();

        uint64 batchEdition = inputs[0].editionNo;
        ImprintStorage.EditionHeader storage hdr = st.editionHeaders[
            batchEdition
        ];
        if (hdr.editionNo == 0) revert EditionMissing();
        if (hdr.isSealed) revert EditionAlreadySealed();

        unchecked {
            for (uint256 i; i < n; ++i) {
                SeedInput calldata sIn = inputs[i];
                if (sIn.editionNo != batchEdition) revert MixedEdition();
                if (sIn.desc.length == 0) revert EmptyDesc();
                if (st.localIndexTaken[batchEdition][sIn.localIndex])
                    revert DuplicateLocalIdx();

                st.localIndexTaken[batchEdition][sIn.localIndex] = true;
                uint256 newId = ++st.nextSeedId;
                st.seeds[newId] = ImprintStorage.ImprintSeed({
                    editionNo: batchEdition,
                    localIndex: sIn.localIndex,
                    subjectId: sIn.subjectId,
                    subjectName: sIn.subjectName,
                    descPtr: SSTORE2.write(sIn.desc),
                    claimed: false
                });

                if (st.firstSeedId[batchEdition] == 0) {
                    st.firstSeedId[batchEdition] = newId;
                }
                st.lastSeedId[batchEdition] = newId;
            }
        }
    }

    function setActiveEdition(uint64 editionNo) external {
        ImprintStorage.Layout storage st = ImprintStorage.layout();

        if (editionNo == 0) {
            st.activeEdition = 0;
            st.activeCursor = 0;
            return;
        }

        ImprintStorage.EditionHeader storage h = st.editionHeaders[editionNo];
        if (h.editionNo == 0) revert UnknownEdition();
        if (!h.isSealed) revert EditionNotSealed();
        if (st.firstSeedId[editionNo] == 0) revert NoSeeds();

        st.activeEdition = editionNo;
        st.activeCursor = st.firstSeedId[editionNo];
    }

    // Getter functions
    function getEditionHeader(uint64 editionNo)
        external
        view
        returns (ImprintStorage.EditionHeader memory)
    {
        return ImprintStorage.layout().editionHeaders[editionNo];
    }

    function getSeed(uint256 seedId)
        external
        view
        returns (ImprintStorage.ImprintSeed memory)
    {
        return ImprintStorage.layout().seeds[seedId];
    }

    function getTokenMeta(uint256 tokenId)
        external
        view
        returns (ImprintStorage.TokenMeta memory)
    {
        return ImprintStorage.layout().meta[tokenId];
    }

    function getDescPtr(uint256 tokenId) external view returns (address) {
        return ImprintStorage.layout().descPtr[tokenId];
    }

    function getRemainingInEdition(uint64 editionNo)
        external
        view
        returns (uint256 remaining)
    {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint256 first = st.firstSeedId[editionNo];
        uint256 last = st.lastSeedId[editionNo];
        if (first == 0 || last == 0) return 0;
        unchecked {
            for (uint256 i = first; i <= last; ++i) {
                if (!st.seeds[i].claimed) ++remaining;
            }
        }
    }

    function getWorldCanon() external view returns (address) {
        return ImprintStorage.layout().worldCanon;
    }

    function isMintPaused() external view returns (bool) {
        return ImprintStorage.layout().mintPaused;
    }

    function getEditionSize(uint64 ed) external view returns (uint256) {
        ImprintStorage.Layout storage st = ImprintStorage.layout();
        uint256 first = st.firstSeedId[ed];
        uint256 last = st.lastSeedId[ed];
        return (first == 0 || last == 0) ? 0 : last - first + 1;
    }

    function setMintPaused(bool paused) external {
        ImprintStorage.layout().mintPaused = paused;
    }
}
