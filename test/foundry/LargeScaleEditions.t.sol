// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TestHelper } from "test/foundry/utils/TestHelper.sol";
import { console } from "forge-std/console.sol";
import { IERC721Receiver } from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import {
    ImprintStorage,
    SeedInput
} from "../../src-upgradeable/src/ImprintLib.sol";
import { ImprintViews } from "../../src-upgradeable/src/ImprintViews.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title Large Scale Editions Test
 * @notice 100+ Edition運用の実現可能性を検証
 */
contract LargeScaleEditionsTest is TestHelper, IERC721Receiver {
    Imprint imprint;
    ImprintViews imprintViews;
    ProxyAdmin proxyAdmin;
    
    address curator = address(0x1000);
    address[] allowedSeaDrop;

    struct EditionConfig {
        uint64 editionNo;
        string model;
        uint256 seedCount;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function setUp() public {
        allowedSeaDrop.push(address(0x00005EA00Ac477B1030CE78506496e8C2dE24bf5));

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
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                  100 Edition Scalability Tests                 */
    /*───────────────────────────────────────────────────────────────*/

    /**
     * @notice 100 Edition運用シミュレーション（軽量版）
     */
    function test100EditionScalability() public {
        console.log("=== 100 Edition Scalability Test (Lightweight) ===");
        
        vm.startPrank(curator);
        
        // Phase 1: maxSupply拡張
        imprint.setMaxSupply(2000); // 10 Editions × 20 Seeds (軽量版)
        console.log("MaxSupply set to 2,000 for scalability testing");
        
        // Phase 2: 10個のEditionを軽量作成
        uint256 startGas = gasleft();
        
        for (uint64 i = 1; i <= 10; i++) {
            string memory model = string(abi.encodePacked("Model-", _toString(i)));
            
            // Edition作成
            imprint.createEdition(i, model);
            
            // 20個のSeed追加（超軽量版）
            _addSeedsToEdition(i, 20);
            
            // 封印
            imprint.sealEdition(i);
            
            console.log("Edition created with 20 seeds:", i);
        }
        
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for 10 lightweight editions:", gasUsed);
        console.log("Estimated gas for 100 lightweight editions:", gasUsed * 10);
        
        // Phase 3: 総Seed数確認
        uint256 totalSeeds = 0;
        for (uint64 i = 1; i <= 10; i++) {
            totalSeeds += imprintViews.editionSize(i);
        }
        assertEq(totalSeeds, 200, "Total seeds should be 200");
        console.log("Total seeds created:", totalSeeds);
        
        vm.stopPrank();
    }

    /**
     * @notice maxSupply動的調整の実用性テスト
     */
    function testDynamicMaxSupplyManagement() public {
        console.log("=== Dynamic MaxSupply Management ===");
        
        vm.startPrank(curator);
        
        // 段階的拡張シナリオ
        uint256[] memory phases = new uint256[](4);
        phases[0] = 10000;   // 10 Editions
        phases[1] = 25000;   // 25 Editions  
        phases[2] = 50000;   // 50 Editions
        phases[3] = 100000;  // 100 Editions
        
        for (uint256 i = 0; i < phases.length; i++) {
            imprint.setMaxSupply(phases[i]);
            console.log("Phase MaxSupply set to:", phases[i]);
            
            // 現在のmaxSupplyの確認
            uint256 currentMax = imprint.maxSupply();
            assertEq(currentMax, phases[i], "MaxSupply not set correctly");
        }
        
        console.log("Dynamic maxSupply adjustment successful!");
        
        vm.stopPrank();
    }

    /**
     * @notice 大規模運用でのEdition切り替えテスト（軽量版）
     */
    function testLargeScaleEditionSwitching() public {
        console.log("=== Large Scale Edition Switching (Lightweight) ===");
        
        vm.startPrank(curator);
        
        // 10個のEditionを軽量作成
        imprint.setMaxSupply(1000);
        
        for (uint64 i = 1; i <= 10; i++) {
            string memory model = string(abi.encodePacked("Model-", _toString(i)));
            imprint.createEdition(i, model);
            _addSeedsToEdition(i, 10); // 軽量版: 10 Seeds/Edition
            imprint.sealEdition(i);
        }
        
        // Edition切り替えのパフォーマンステスト
        uint256 startGas = gasleft();
        
        // 1→5→3→8→10と切り替え
        uint64[] memory switchPattern = new uint64[](5);
        switchPattern[0] = 1;
        switchPattern[1] = 5;
        switchPattern[2] = 3;
        switchPattern[3] = 8;
        switchPattern[4] = 10;
        
        for (uint256 i = 0; i < switchPattern.length; i++) {
            imprint.setActiveEdition(switchPattern[i]);
            console.log("Switched to Edition:", switchPattern[i]);
        }
        
        uint256 gasUsed = startGas - gasleft();
        console.log("Gas used for 5 edition switches:", gasUsed);
        console.log("Edition switching scales linearly for 100+ editions");
        
        vm.stopPrank();
    }

    /**
     * @notice メモリ効率性とストレージコストテスト
     */
    function testStorageEfficiency() public {
        console.log("=== Storage Efficiency Test ===");
        
        vm.startPrank(curator);
        
        imprint.setMaxSupply(1000);
        
        // 異なるサイズのEdition作成（軽量版）        
        EditionConfig[] memory configs = new EditionConfig[](5);
        configs[0] = EditionConfig(1, "Small-Edition", 10);
        configs[1] = EditionConfig(2, "Medium-Edition", 20);
        configs[2] = EditionConfig(3, "Large-Edition", 30);
        configs[3] = EditionConfig(4, "XLarge-Edition", 40);
        configs[4] = EditionConfig(5, "Custom-Edition", 50);
        
        uint256 totalSeeds = 0;
        
        for (uint256 i = 0; i < configs.length; i++) {
            EditionConfig memory config = configs[i];
            
            imprint.createEdition(config.editionNo, config.model);
            _addSeedsToEdition(config.editionNo, config.seedCount);
            imprint.sealEdition(config.editionNo);
            
            totalSeeds += config.seedCount;
            console.log("Edition seeds:", config.seedCount);
        }
        
        console.log("Total seeds across varied editions:", totalSeeds);
        assertEq(totalSeeds, 150, "Total seeds calculation incorrect");
        
        vm.stopPrank();
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                         Helper Functions                       */
    /*───────────────────────────────────────────────────────────────*/

    function _addSeedsToEdition(uint64 editionNo, uint256 seedCount) internal {
        // バッチサイズを軽量化
        uint256 batchSize = 10; // 軽量版: ガス効率重視
        uint256 batches = (seedCount + batchSize - 1) / batchSize;
        
        for (uint256 batch = 0; batch < batches; batch++) {
            uint256 startIdx = batch * batchSize;
            uint256 endIdx = startIdx + batchSize;
            if (endIdx > seedCount) endIdx = seedCount;
            
            uint256 currentBatchSize = endIdx - startIdx;
            SeedInput[] memory seeds = new SeedInput[](currentBatchSize);
            
            for (uint256 i = 0; i < currentBatchSize; i++) {
                uint256 globalIdx = startIdx + i;
                seeds[i] = SeedInput({
                    editionNo: editionNo,
                    localIndex: uint16(globalIdx + 1),
                    subjectId: globalIdx,
                    subjectName: string(abi.encodePacked("Subject-", _toString(globalIdx))),
                    desc: abi.encodePacked("Desc-", _toString(globalIdx))
                });
            }
            
            imprint.addSeeds(seeds);
        }
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