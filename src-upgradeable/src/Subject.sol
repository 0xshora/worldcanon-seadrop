// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*── OpenZeppelin (remappings.txt → openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/) ──*/
import {ERC721}  from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {Base64}  from "openzeppelin-contracts/utils/Base64.sol";

/*── Imprint interface ──*/
interface IImprint { 
    function descriptor() external view returns (address);
}
interface IImprintDescriptor { 
    function tokenImage(uint256) external view returns (string memory); 
}

/*── LibNormalize ──*/
import {LibNormalize} from "./LibNormalize.sol";

using LibNormalize for string;

/*================================================================================================
                                   Subject – Immutable ERC-721
================================================================================================*/
contract Subject is ERC721, Ownable {
    struct SubjectMeta {
        uint64 addedEditionNo;
        uint256 latestImprintId;
        uint256 latestTimestamp;
    }

    mapping(uint256 => SubjectMeta) public subjectMeta;
    // tokenId to name
    mapping(uint256 => string)      private _subjectNames;
    // name to tokenId(1-index)
    mapping(bytes32 => uint256) private _nameHashToIdPlus1;

    uint256  public totalSupply;
    address  public imprintContract;

    /*───────────── events ─────────────*/
    event ImprintContractSet(address indexed imprint);
    event LatestImprintUpdated(uint256 indexed tokenId, uint256 indexed imprintId);

    /*───────────── modifiers ───────────*/
    modifier onlyImprint() {
        require(msg.sender == imprintContract, "onlyImprint");
        _;
    }
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}


    function syncFromImprint(
        string calldata subjectNameParam,
        uint256 imprintId,
        uint64  ts
    ) external onlyImprint {
        bytes32 h       = subjectNameParam.normHash();
        uint256 idPlus1 = _nameHashToIdPlus1[h];
        uint256 tokenId;

        /*――― ① まだ存在しない場合＝新規 Subject ―――*/
        if (idPlus1 == 0) {
            tokenId = totalSupply;              // 次の ID
            _mint(owner(), tokenId);            // Owner (= キュレーター) 保有で発行
            _subjectNames[tokenId]   = subjectNameParam;
            _nameHashToIdPlus1[h]    = tokenId + 1; // +1 オフセット保存
            subjectMeta[tokenId].addedEditionNo = 0; // 動的追加なので 0
            totalSupply += 1;
        } else {
            tokenId = idPlus1 - 1;              // 既存 ID
        }

        /*――― ② より新しい timestamp なら latest を更新 ―――*/
        if (ts > subjectMeta[tokenId].latestTimestamp) {
            subjectMeta[tokenId].latestImprintId = imprintId;
            subjectMeta[tokenId].latestTimestamp = ts;
            emit LatestImprintUpdated(tokenId, imprintId);
        }
    }

    /*────────────────────────── Owner-only ──────────────────────────*/
    function mintInitial(string[] calldata names) external onlyOwner {
        require(totalSupply == 0, "initialized");
        uint256 n = names.length;
        // require(n == 1000, "need exactly 1000 names");
        for (uint256 i; i < n; ++i) {
            _mint(msg.sender, i);
            _subjectNames[i]              = names[i];
            subjectMeta[i].addedEditionNo = 0;

            bytes32 h = names[i].normHash();
            require(_nameHashToIdPlus1[h] == 0, "dup");
            _nameHashToIdPlus1[h] = i + 1;  // id + 1を保存
            totalSupply += 1;
        }
    }

    /*────────────────────────── Owner-only ──────────────────────────*/
    function setImprintContract(address imprint) external onlyOwner {
        require(imprintContract == address(0), "already set");
        require(imprint != address(0),         "zero addr");
        imprintContract = imprint;
        emit ImprintContractSet(imprint);
    }

    function addSubjects(string[] calldata names, uint64 editionNo) external onlyOwner {
        uint256 start = totalSupply; uint256 n = names.length; require(n > 0, "empty");
        for (uint256 i; i < n; ++i) {
            uint256 id = start + i;
            _mint(msg.sender, id);
            _subjectNames[id]              = names[i];
            subjectMeta[id].addedEditionNo = editionNo;
            
            bytes32 h = names[i].normHash();
            require(_nameHashToIdPlus1[h] == 0, "dup subject");   // Guard
            _nameHashToIdPlus1[h] = id + 1; 
        }
        totalSupply += n;
    }

    function setLatest(uint256 tokenId, uint256 imprintId) external onlyOwner {
        require(_exists(tokenId), "nonexistent");
        subjectMeta[tokenId].latestImprintId = imprintId;
        emit LatestImprintUpdated(tokenId, imprintId);
    }

    /*────────────────────────── tokenURI ───────────────────────────*/
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "nonexistent");
        SubjectMeta memory m = subjectMeta[tokenId];
        string memory name_  = _subjectNames[tokenId];

        string memory imageURI = (m.latestImprintId == 0 || imprintContract == address(0))
            ? _placeholderSVG(name_)
            : IImprintDescriptor(IImprint(imprintContract).descriptor()).tokenImage(m.latestImprintId);

        bytes memory json = abi.encodePacked(
            '{"name":"#', Strings.toString(tokenId), ' - ', name_, '"',
            ',"attributes":['
                '{"trait_type":"Token ID","value":"', Strings.toString(tokenId), '"},'
                '{"trait_type":"Latest Imprint ID","value":"', Strings.toString(m.latestImprintId), '"}'
            '],"image":"', imageURI, '"}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /*──────────────────────── placeholder SVG ──────────────────────*/
    function _placeholderSVG(string memory txt) internal pure returns (string memory) {
        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">',
            '<rect width="100%" height="100%" fill="black"/>',
            '<foreignObject x="10" y="10" width="330" height="330">',
            '<div xmlns="http://www.w3.org/1999/xhtml" style="color:white;font:20px/1.4 Courier New,monospace;',
            'overflow-wrap:anywhere;text-align:center;display:flex;justify-content:center;align-items:center;height:100%;">',
            txt,
            '</div></foreignObject></svg>'
        );
        return string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(svg)));
    }

    /*────────────────────────── view ───────────────────────────────*/
    function subjectName(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "nonexistent");
        return _subjectNames[tokenId];
    }
}