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
 * @title Gas Analysis Test
 * @notice 各オペレーションのガス使用量を詳細分析
 */
contract GasAnalysisTest is TestHelper, IERC721Receiver {
    Imprint imprint;
    ImprintViews imprintViews;
    ProxyAdmin proxyAdmin;
    
    address curator = address(0x1000);
    address[] allowedSeaDrop;

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
        
        vm.prank(curator);
        imprint.setMaxSupply(100000);
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                     Individual Gas Analysis                    */
    /*───────────────────────────────────────────────────────────────*/

    /**
     * @notice createEdition()のガス使用量分析
     */
    function testGasCreateEdition() public {
        console.log("=== Gas Analysis: createEdition ===");
        
        vm.startPrank(curator);
        
        // 単一Edition作成のガス測定
        uint256 startGas = gasleft();
        imprint.createEdition(1, "Test-Model-1");
        uint256 gasUsed = startGas - gasleft();
        
        console.log("createEdition gas: %d", gasUsed);
        
        // 複数Edition作成のガス変化
        for (uint64 i = 2; i <= 5; i++) {
            startGas = gasleft();
            imprint.createEdition(i, string(abi.encodePacked("Test-Model-", _toString(i))));
            gasUsed = startGas - gasleft();
            console.log("createEdition %d gas: %d", i, gasUsed);
        }
        
        vm.stopPrank();
    }

    /**
     * @notice addSeeds()のバッチサイズ別ガス分析
     */
    function testGasAddSeedsBatchSizes() public {
        console.log("=== Gas Analysis: addSeeds batch sizes ===");
        
        vm.startPrank(curator);
        
        // Edition作成
        imprint.createEdition(1, "Test-Model");
        
        // 異なるバッチサイズでのガス測定
        uint256[] memory batchSizes = new uint256[](6);
        batchSizes[0] = 1;
        batchSizes[1] = 10;
        batchSizes[2] = 25;
        batchSizes[3] = 50;
        batchSizes[4] = 100;
        batchSizes[5] = 200;
        
        uint256 globalSeedCounter = 0;
        
        for (uint256 i = 0; i < batchSizes.length; i++) {
            uint256 batchSize = batchSizes[i];
            
            SeedInput[] memory seeds = new SeedInput[](batchSize);
            for (uint256 j = 0; j < batchSize; j++) {
                seeds[j] = SeedInput({
                    editionNo: 1,
                    localIndex: uint16(globalSeedCounter + j + 1),
                    subjectId: globalSeedCounter + j,
                    subjectName: string(abi.encodePacked("Subject-", _toString(globalSeedCounter + j))),
                    desc: abi.encodePacked("Desc-", _toString(globalSeedCounter + j))
                });
            }
            
            uint256 startGas = gasleft();
            imprint.addSeeds(seeds);
            uint256 gasUsed = startGas - gasleft();
            
            console.log("addSeeds batch size %d: %d gas", batchSize, gasUsed);
            console.log("  Gas per seed: %d", gasUsed / batchSize);
            
            globalSeedCounter += batchSize;
        }
        
        vm.stopPrank();
    }

    /**
     * @notice sealEdition()のガス分析
     */
    function testGasSealEdition() public {
        console.log("=== Gas Analysis: sealEdition ===");
        
        vm.startPrank(curator);
        
        // 異なるサイズのEditionを封印
        uint256[] memory seedCounts = new uint256[](4);
        seedCounts[0] = 10;
        seedCounts[1] = 50;
        seedCounts[2] = 100;
        seedCounts[3] = 500;
        
        for (uint256 i = 0; i < seedCounts.length; i++) {
            uint64 editionNo = uint64(i + 1);
            uint256 seedCount = seedCounts[i];
            
            // Edition作成とSeed追加
            imprint.createEdition(editionNo, string(abi.encodePacked("Model-", _toString(editionNo))));
            _addSeedsToEdition(editionNo, seedCount);
            
            // 封印のガス測定
            uint256 startGas = gasleft();
            imprint.sealEdition(editionNo);
            uint256 gasUsed = startGas - gasleft();
            
            console.log("sealEdition (Edition %d, %d seeds): %d gas", editionNo, seedCount, gasUsed);
        }
        
        vm.stopPrank();
    }

    /**
     * @notice setActiveEdition()のガス分析
     */
    function testGasSetActiveEdition() public {
        console.log("=== Gas Analysis: setActiveEdition ===");
        
        vm.startPrank(curator);
        
        // 複数Editionを準備
        for (uint64 i = 1; i <= 10; i++) {
            imprint.createEdition(i, string(abi.encodePacked("Model-", _toString(i))));
            _addSeedsToEdition(i, 100);
            imprint.sealEdition(i);
        }
        
        // Edition切り替えのガス測定
        uint64[] memory switchPattern = new uint64[](6);
        switchPattern[0] = 1;
        switchPattern[1] = 5;
        switchPattern[2] = 10;
        switchPattern[3] = 3;
        switchPattern[4] = 7;
        switchPattern[5] = 2;
        
        for (uint256 i = 0; i < switchPattern.length; i++) {
            uint256 startGas = gasleft();
            imprint.setActiveEdition(switchPattern[i]);
            uint256 gasUsed = startGas - gasleft();
            
            console.log("setActiveEdition to %d: %d gas", switchPattern[i], gasUsed);
        }
        
        vm.stopPrank();
    }

    /**
     * @notice 大量Seed追加の累積ガス分析
     */
    function testGasCumulativeSeeds() public {
        console.log("=== Gas Analysis: Cumulative Seeds ===");
        
        vm.startPrank(curator);
        
        imprint.createEdition(1, "Cumulative-Test");
        
        // 100個ずつ追加して累積効果を測定
        uint256 batchSize = 100;
        uint256 maxBatches = 10; // 1,000個まで
        
        for (uint256 batch = 0; batch < maxBatches; batch++) {
            SeedInput[] memory seeds = new SeedInput[](batchSize);
            
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 globalIdx = batch * batchSize + i;
                seeds[i] = SeedInput({
                    editionNo: 1,
                    localIndex: uint16(globalIdx + 1),
                    subjectId: globalIdx,
                    subjectName: string(abi.encodePacked("Subject-", _toString(globalIdx))),
                    desc: abi.encodePacked("Desc-", _toString(globalIdx))
                });
            }
            
            uint256 startGas = gasleft();
            imprint.addSeeds(seeds);
            uint256 gasUsed = startGas - gasleft();
            
            console.log("Batch %d gas: %d", batch + 1, gasUsed);
        }
        
        uint256 totalSeeds = imprintViews.editionSize(1);
        console.log("Total seeds added: %d", totalSeeds);
        
        vm.stopPrank();
    }

    /**
     * @notice ストレージコスト分析（SSTORE2）
     */
    function testGasStorageCosts() public {
        console.log("=== Gas Analysis: Storage Costs ===");
        
        vm.startPrank(curator);
        
        imprint.createEdition(1, "Storage-Test");
        
        // 異なるdescサイズでの比較
        uint256[] memory descSizes = new uint256[](4);
        descSizes[0] = 10;   // 小さなdesc
        descSizes[1] = 50;   // 中程度のdesc
        descSizes[2] = 100;  // 大きなdesc
        descSizes[3] = 200;  // 非常に大きなdesc
        
        for (uint256 i = 0; i < descSizes.length; i++) {
            uint256 descSize = descSizes[i];
            
            // 大きなdescデータを作成
            bytes memory largeDesc = new bytes(descSize);
            for (uint256 j = 0; j < descSize; j++) {
                largeDesc[j] = bytes1(uint8(65 + (j % 26))); // A-Z繰り返し
            }
            
            SeedInput[] memory seeds = new SeedInput[](1);
            seeds[0] = SeedInput({
                editionNo: 1,
                localIndex: uint16(i + 1),
                subjectId: i,
                subjectName: string(abi.encodePacked("Subject-", _toString(i))),
                desc: largeDesc
            });
            
            uint256 startGas = gasleft();
            imprint.addSeeds(seeds);
            uint256 gasUsed = startGas - gasleft();
            
            console.log("Storage bytes desc gas:", descSize, gasUsed);
            console.log("  Gas per byte:", gasUsed / descSize);
        }
        
        vm.stopPrank();
    }

    /*───────────────────────────────────────────────────────────────*/
    /*                         Helper Functions                       */
    /*───────────────────────────────────────────────────────────────*/

    function _addSeedsToEdition(uint64 editionNo, uint256 seedCount) internal {
        uint256 batchSize = 50;
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