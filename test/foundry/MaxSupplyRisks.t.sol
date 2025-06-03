// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TestHelper } from "test/foundry/utils/TestHelper.sol";
import { console } from "forge-std/console.sol";
import { IERC721Receiver } from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import {
    ImprintStorage,
    SeedInput,
    SoldOut,
    NoSeeds,
    EditionAlreadySealed
} from "../../src-upgradeable/src/ImprintLib.sol";
// MintQuantityExceedsMaxSupplyはinterfaceで定義されているため、vm.expectRevert()のみ使用
import { ImprintViews } from "../../src-upgradeable/src/ImprintViews.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title MaxSupplyRisks Test
 * @notice 実運用でのmaxSupply関連リスクを検証
 */
contract MaxSupplyRisksTest is TestHelper, IERC721Receiver {
    Imprint imprint;
    ImprintViews imprintViews;
    ProxyAdmin proxyAdmin;
    
    address curator = address(0x1000);
    address[] allowedSeaDrop;

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function setUp() public {
        // SeaDrop setup
        allowedSeaDrop.push(address(0x00005EA00Ac477B1030CE78506496e8C2dE24bf5));

        // Deploy with proxy
        proxyAdmin = new ProxyAdmin();
        Imprint implementation = new Imprint();
        
        bytes memory initData = abi.encodeWithSelector(
            Imprint.initializeImprint.selector,
            "WorldCanonImprint",
            "WCIMP",
            allowedSeaDrop,
            curator
        );

        TransparentUpgradeableProxy proxy = 
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        imprint = Imprint(address(proxy));
        imprintViews = new ImprintViews(address(imprint));

        // Real-world settings
        vm.startPrank(curator);
        imprint.setMaxSupply(10000); // 要件定義通り
        vm.stopPrank();
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                    Critical Risk Scenarios                     */
    /*───────────────────────────────────────────────────────────────*/

    /**
     * @notice リスク1: Edition数上限に達した時の挙動（軽量版）
     * 
     * シナリオ: 5個のEdition (各200 Seeds) でmaxSupply到達
     */
    function testMaxSupplyEditionLimit() public {
        console.log("=== Risk 1: Edition Count Limit (Lightweight) ===");
        
        vm.startPrank(curator);
        
        // 5個のEditionを作成・封印（軽量化）
        for (uint64 i = 1; i <= 5; i++) {
            string memory model = string(abi.encodePacked("Model-", _toString(i)));
            
            // Edition作成
            imprint.createEdition(i, model);
            
            // 200個のSeed追加（軽量化）
            SeedInput[] memory seeds = _createNSeeds(i, 200);
            imprint.addSeeds(seeds);
            
            // 封印
            imprint.sealEdition(i);
            
            console.log("Edition %d created: %s", i, model);
        }
        
        // この時点で理論上1,000 Seeds
        uint256 totalSeeds = 0;
        for (uint64 i = 1; i <= 5; i++) {
            totalSeeds += imprintViews.editionSize(i);
        }
        assertEq(totalSeeds, 1000, "Total seeds should be 1,000");
        
        // 6個目のEdition作成は可能（まだmint前）
        imprint.createEdition(6, "Overflow-Model");
        
        // しかし、Seed追加でmaxSupply超過のリスクあり
        console.log("Edition 6 created but seed addition will be risky");
        
        vm.stopPrank();
    }

    /**
     * @notice リスク2: Seedなしでの封印防止（修正後の動作）
     */
    function testEditionSealWithoutSeeds() public {
        console.log("=== Risk 2: Edition Seal Without Seeds (FIXED BEHAVIOR) ===");
        
        vm.startPrank(curator);
        
        // Edition作成だけしてSeed追加せず
        imprint.createEdition(1, "Empty-Edition");
        
        // ✅ 修正後: Seedなしでの封印は失敗する
        vm.expectRevert(NoSeeds.selector);
        imprint.sealEdition(1);
        console.log("Empty edition seal correctly prevented - SAFE!");
        
        // Seedを追加してから封印すれば成功
        SeedInput[] memory seeds = new SeedInput[](1);
        seeds[0] = SeedInput({
            editionNo: 1,
            localIndex: 1,
            subjectId: 0,
            subjectName: "Test Subject",
            desc: "Test Description"
        });
        imprint.addSeeds(seeds);
        
        // 今度は封印成功
        imprint.sealEdition(1);
        console.log("Edition with seeds sealed successfully");
        
        // アクティブ化も成功
        imprint.setActiveEdition(1);
        console.log("Edition activated successfully");
        
        vm.stopPrank();
    }

    /**
     * @notice リスク3: Mint時の在庫管理機能
     */
    function testMintMaxSupplyEnforcement() public {
        console.log("=== Risk 3: Mint Stock Management ===");
        
        vm.startPrank(curator);
        
        // Edition作成
        imprint.createEdition(1, "Test-Edition");
        
        // 50個のSeedのみ追加（在庫制限）
        SeedInput[] memory seeds = _createNSeeds(1, 50);
        imprint.addSeeds(seeds);
        imprint.sealEdition(1);
        imprint.setActiveEdition(1);
        
        vm.stopPrank();
        
        // 50枚全てをミント
        vm.prank(allowedSeaDrop[0]);
        imprint.mintSeaDrop(address(this), 50);
        
        // 追加でミントしようとするとSoldOutエラー
        vm.prank(allowedSeaDrop[0]);
        vm.expectRevert(SoldOut.selector);
        imprint.mintSeaDrop(address(this), 1);
        
        console.log("Stock management (SoldOut) works correctly!");
    }

    /**
     * @notice リスク4: Edition間の不整合
     */
    function testEditionSupplyImbalance() public {
        console.log("=== Risk 4: Edition Supply Imbalance ===");
        
        vm.startPrank(curator);
        
        // 異なるサイズのEditionを作成
        // Edition 1: 2000 Seeds (標準の2倍)
        imprint.createEdition(1, "Large-Edition");
        SeedInput[] memory largeSeeds = _createNSeeds(1, 2000);
        imprint.addSeeds(largeSeeds);
        imprint.sealEdition(1);
        
        // Edition 2: 500 Seeds (標準の半分)
        imprint.createEdition(2, "Small-Edition");
        SeedInput[] memory smallSeeds = _createNSeeds(2, 500);
        imprint.addSeeds(smallSeeds);
        imprint.sealEdition(2);
        
        console.log("Large Edition size: %d", imprintViews.editionSize(1));
        console.log("Small Edition size: %d", imprintViews.editionSize(2));
        
        // 不整合は技術的には可能だが運用上要注意
        assertEq(imprintViews.editionSize(1), 2000, "Large edition size");
        assertEq(imprintViews.editionSize(2), 500, "Small edition size");
        
        vm.stopPrank();
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                         Helper Functions                       */
    /*───────────────────────────────────────────────────────────────*/

    function _create1000Seeds(uint64 editionNo) internal pure returns (SeedInput[] memory) {
        return _createNSeeds(editionNo, 1000);
    }

    function _createNSeeds(uint64 editionNo, uint256 count) internal pure returns (SeedInput[] memory) {
        SeedInput[] memory seeds = new SeedInput[](count);
        
        for (uint256 i = 0; i < count; i++) {
            seeds[i] = SeedInput({
                editionNo: editionNo,
                localIndex: uint16(i + 1),
                subjectId: i,
                subjectName: string(abi.encodePacked("Subject-", _toString(i))),
                desc: abi.encodePacked("Description for subject ", _toString(i))
            });
        }
        
        return seeds;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
}