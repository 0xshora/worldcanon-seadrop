// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { TestHelper } from "test/foundry/utils/TestHelper.sol";

import { Subject } from "../../src-upgradeable/src/Subject.sol";
import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import { ImprintViews } from "../../src-upgradeable/src/ImprintViews.sol";
import { ImprintDescriptor } from "../../src-upgradeable/src/ImprintDescriptor.sol";

import {
    ImprintStorage,
    SeedInput
} from "../../src-upgradeable/src/ImprintLib.sol";

import {
    TransparentUpgradeableProxy
} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    ProxyAdmin
} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {
    PublicDrop
} from "../../src-upgradeable/src/lib/SeaDropStructsUpgradeable.sol";
import {
    IERC721Receiver
} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title WorldCanonPerformanceTest
 * @notice パフォーマンス、ガス効率性、スケーラビリティの包括的テスト
 * 
 * テストカテゴリ:
 * 1. ガス使用量の最適化検証
 * 2. 大量データ処理のスケーラビリティ
 * 3. メモリ効率性とストレージ最適化
 * 4. バッチ処理の効率性比較
 * 5. SSTORE2によるストレージコスト削減効果
 */
contract WorldCanonPerformanceTest is TestHelper, IERC721Receiver {
    /*──────────── コントラクトインスタンス ────────────*/
    Subject public subject;
    Imprint public imprint;
    ImprintViews public imprintViews;
    ImprintDescriptor public imprintDescriptor;
    ProxyAdmin public proxyAdmin;

    /*──────────── テストアクター ────────────*/
    address public owner = address(0x1000);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);

    /*──────────── パフォーマンス測定用構造体 ────────────*/
    struct GasMetrics {
        uint256 gasUsed;
        uint256 gasPrice;
        uint256 totalCost;
        uint256 timestamp;
    }

    struct BatchMetrics {
        uint256 batchSize;
        uint256 totalGas;
        uint256 gasPerItem;
        uint256 executionTime;
    }

    /*──────────── セットアップ ────────────*/
    function setUp() public {
        // 基本コントラクトデプロイ
        proxyAdmin = new ProxyAdmin();
        subject = new Subject("World Canon Subjects", "WCSBJ");
        
        // Subject の所有者をownerに移転
        subject.transferOwnership(owner);

        Imprint implementation = new Imprint();
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        bytes memory initData = abi.encodeWithSelector(
            Imprint.initializeImprint.selector,
            "WorldCanonImprint",
            "WCIMP",
            allowedSeaDrop,
            owner
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        imprint = Imprint(address(proxy));
        imprintViews = new ImprintViews(address(imprint));
        imprintDescriptor = new ImprintDescriptor(address(imprint));

        // 基本設定
        vm.startPrank(owner);
        imprint.setDescriptor(address(imprintDescriptor));
        imprint.setMaxSupply(10000);
        imprint.setWorldCanon(address(subject));
        
        PublicDrop memory publicDrop = PublicDrop(
            0.01 ether, uint48(block.timestamp), uint48(block.timestamp) + 7 days,
            25, 250, false
        );
        imprint.updatePublicDrop(address(seadrop), publicDrop);
        imprint.updateCreatorPayoutAddress(address(seadrop), owner);
        vm.stopPrank();

        // ETH配布
        vm.deal(owner, 1000 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function onERC721Received(address, address, uint256, bytes calldata) 
        external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                       Gas Optimization Tests                     */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice ガス効率性テスト: バッチサイズ別の最適化
     */
    function testBatchSizeOptimization() public {
        console.log("Batch Size Optimization Test started");

        vm.startPrank(owner);
        imprint.createEdition(1, "GasOptimizationModel");

        // 異なるバッチサイズでのガス使用量を測定
        uint256[] memory batchSizes = new uint256[](5);
        batchSizes[0] = 1;
        batchSizes[1] = 10;
        batchSizes[2] = 50;
        batchSizes[3] = 100;
        batchSizes[4] = 200;

        BatchMetrics[] memory metrics = new BatchMetrics[](5);

        for (uint256 i = 0; i < batchSizes.length; i++) {
            uint256 batchSize = batchSizes[i];
            
            // 新しいEditionを作成（テスト分離のため）
            imprint.createEdition(uint64(i + 2), string(abi.encodePacked("Model_", _toString(i))));
            
            // Seeds準備
            SeedInput[] memory seeds = new SeedInput[](batchSize);
            for (uint256 j = 0; j < batchSize; j++) {
                seeds[j] = SeedInput({
                    editionNo: uint64(i + 2),
                    localIndex: uint16(j + 1),
                    subjectId: j,
                    subjectName: string(abi.encodePacked("Subject_", _toString(j))),
                    desc: abi.encodePacked("Description_", _toString(j))
                });
            }

            // ガス測定
            uint256 gasStart = gasleft();
            uint256 timeStart = block.timestamp;
            
            imprint.addSeeds(seeds);
            
            uint256 gasUsed = gasStart - gasleft();
            uint256 timeEnd = block.timestamp;

            metrics[i] = BatchMetrics({
                batchSize: batchSize,
                totalGas: gasUsed,
                gasPerItem: gasUsed / batchSize,
                executionTime: timeEnd - timeStart
            });

            console.log("Batch Size: %d, Total Gas: %d, Gas/Item: %d", 
                       batchSize, gasUsed, gasUsed / batchSize);
        }

        // 効率性の検証：バッチサイズが大きいほど、アイテムあたりのガスが少ないはず
        for (uint256 i = 1; i < metrics.length; i++) {
            assertTrue(
                metrics[i].gasPerItem <= metrics[i-1].gasPerItem,
                "Batch processing efficiency not improved"
            );
        }

        vm.stopPrank();
        console.log(" Batch Size Optimization Test SUCCESS");
    }

    /**
     * @notice SSTORE2効率性テスト: 従来ストレージとの比較
     */
    function testSSTORE2Efficiency() public {
        console.log("SSTORE2 Efficiency Test started");

        vm.startPrank(owner);
        imprint.createEdition(1, "SSTORE2TestModel");

        // 異なるサイズのデータでSSTORE2効率性をテスト
        string[] memory testDescriptions = new string[](4);
        testDescriptions[0] = "Short desc";
        testDescriptions[1] = "Medium length description that spans multiple words and contains meaningful content";
        testDescriptions[2] = "Very long description that contains extensive details about the subject matter, including philosophical perspectives, historical context, and contemporary relevance that would typically be generated by advanced language models";
        testDescriptions[3] = "Extremely comprehensive description that goes into extraordinary detail about every aspect of the subject, covering historical significance, philosophical implications, cultural context, scientific understanding, artistic interpretations, and future projections, representing the kind of thorough analysis that advanced AI systems might produce when given unlimited token budgets";

        uint256[] memory gasUsages = new uint256[](4);

        for (uint256 i = 0; i < testDescriptions.length; i++) {
            SeedInput[] memory seeds = new SeedInput[](1);
            seeds[0] = SeedInput({
                editionNo: 1,
                localIndex: uint16(i + 1),
                subjectId: i,
                subjectName: string(abi.encodePacked("Subject_", _toString(i))),
                desc: abi.encodePacked(testDescriptions[i])
            });

            uint256 gasStart = gasleft();
            imprint.addSeeds(seeds);
            gasUsages[i] = gasStart - gasleft();

            console.log("Description Length: %d bytes, Gas Used: %d", 
                       bytes(testDescriptions[i]).length, gasUsages[i]);
        }

        // SSTORE2のスケーラビリティ検証：長いデータでも効率的であることを確認
        // ガス使用量の増加が線形に近いことを検証
        uint256 shortGas = gasUsages[0];
        uint256 longGas = gasUsages[3];
        uint256 shortLength = bytes(testDescriptions[0]).length;
        uint256 longLength = bytes(testDescriptions[3]).length;
        
        uint256 gasPerByte = (longGas - shortGas) * 1000 / (longLength - shortLength);
        console.log("Gas per byte (extrapolated): %d", gasPerByte);

        // 妥当なガス効率性であることを確認（1バイトあたり1000ガス未満）
        assertTrue(gasPerByte < 1000, "SSTORE2 efficiency low");

        vm.stopPrank();
        console.log(" SSTORE2 Efficiency Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                     Scalability Stress Tests                    */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice スケーラビリティテスト: 大量Subject処理
     */
    function testLargeScaleSubjectProcessing() public {
        console.log("Large Scale Subject Processing Test started");

        // 1000件のSubjectを分割してミント（ガス制限対策）
        uint256 totalSubjects = 1000;
        uint256 batchSize = 100;
        uint256 batches = totalSubjects / batchSize;

        uint256 totalGasUsed = 0;

        for (uint256 batch = 0; batch < batches; batch++) {
            string[] memory subjectBatch = new string[](batchSize);
            
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 globalIndex = batch * batchSize + i;
                subjectBatch[i] = string(abi.encodePacked("Subject_", _toString(globalIndex)));
            }

            uint256 gasStart = gasleft();
            
            if (batch == 0) {
                // 初回は mintInitial
                vm.prank(owner);
                subject.mintInitial(subjectBatch);
            } else {
                // 2回目以降は addSubjects
                vm.prank(owner);
                subject.addSubjects(subjectBatch, uint64(batch));
            }
            
            uint256 gasUsed = gasStart - gasleft();
            totalGasUsed += gasUsed;

            // console.log("Batch %s/%s: %s subjects, Gas: %s", 
            //            _toString(batch + 1), _toString(batches), _toString(batchSize), _toString(gasUsed));
        }

        // 検証
        assertEq(subject.totalSupply(), totalSubjects, "Total Subject count incorrect");
        
        console.log("Total Gas Used for %d subjects: %d", totalSubjects, totalGasUsed);
        console.log("Average Gas per Subject: %d", totalGasUsed / totalSubjects);

        // 妥当なガス使用量であることを確認（1 Subjectあたり10万ガス未満）
        assertTrue(totalGasUsed / totalSubjects < 100000, "Subject processing gas efficiency low");

        console.log(" Large Scale Subject Processing Test SUCCESS");
    }

    /**
     * @notice ストレステスト: 大量Edition・Seed処理
     */
    function testMassiveEditionSeedProcessing() public {
        console.log("Massive Edition Seed Processing Test started");

        vm.startPrank(owner);

        // 複数Editionの大量Seed処理
        uint256 editionCount = 5;
        uint256 seedsPerEdition = 200;

        uint256 totalGasUsed = 0;

        for (uint256 ed = 1; ed <= editionCount; ed++) {
            // Edition作成
            string memory modelName = string(abi.encodePacked("Model_", _toString(ed)));
            imprint.createEdition(uint64(ed), modelName);

            // 大量Seeds追加（分割処理）
            uint256 seedBatchSize = 50;
            uint256 seedBatches = seedsPerEdition / seedBatchSize;

            for (uint256 batch = 0; batch < seedBatches; batch++) {
                SeedInput[] memory seeds = new SeedInput[](seedBatchSize);
                
                for (uint256 i = 0; i < seedBatchSize; i++) {
                    uint256 localIndex = batch * seedBatchSize + i + 1;
                    seeds[i] = SeedInput({
                        editionNo: uint64(ed),
                        localIndex: uint16(localIndex),
                        subjectId: localIndex - 1,
                        subjectName: string(abi.encodePacked("Subject_", _toString(localIndex - 1))),
                        desc: abi.encodePacked("Edition_", _toString(ed), "_Desc_", _toString(localIndex))
                    });
                }

                uint256 gasStart = gasleft();
                imprint.addSeeds(seeds);
                uint256 gasUsed = gasStart - gasleft();
                totalGasUsed += gasUsed;
            }

            // Edition封印
            imprint.sealEdition(uint64(ed));

            console.log("Edition %d completed: %d seeds", ed, seedsPerEdition);
        }

        vm.stopPrank();

        // 検証
        for (uint256 ed = 1; ed <= editionCount; ed++) {
            assertEq(imprintViews.editionSize(uint64(ed)), seedsPerEdition, "Edition size incorrect");
            
            ImprintStorage.EditionHeader memory header = imprintViews.getEditionHeader(uint64(ed));
            assertTrue(header.isSealed, "Edition not sealed");
        }

        uint256 totalSeeds = editionCount * seedsPerEdition;
        console.log("Total Seeds Processed: %d", totalSeeds);
        console.log("Total Gas Used: %d", totalGasUsed);
        console.log("Average Gas per Seed: %d", totalGasUsed / totalSeeds);

        // 妥当なガス効率性を確認
        assertTrue(totalGasUsed / totalSeeds < 50000, "Seed processing gas efficiency low");

        console.log(" Massive Edition Seed Processing Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                       Mint Performance Tests                    */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice ミントパフォーマンステスト: 大量同時ミント
     */
    function testHighVolumeSimultaneousMinting() public {
        console.log("High Volume Simultaneous Minting Test started");

        // テスト用Edition準備
        vm.startPrank(owner);
        imprint.createEdition(1, "HighVolumeModel");
        
        // 1000件のSeeds作成（大量ミントテスト用）
        uint256 totalSeeds = 1000;
        uint256 batchSize = 100;
        
        for (uint256 batch = 0; batch < totalSeeds / batchSize; batch++) {
            SeedInput[] memory seeds = new SeedInput[](batchSize);
            
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 globalIndex = batch * batchSize + i;
                seeds[i] = SeedInput({
                    editionNo: 1,
                    localIndex: uint16(globalIndex + 1),
                    subjectId: globalIndex,
                    subjectName: string(abi.encodePacked("Subject_", _toString(globalIndex))),
                    desc: abi.encodePacked("HV_Desc_", _toString(globalIndex))
                });
            }
            
            imprint.addSeeds(seeds);
        }
        
        imprint.sealEdition(1);
        imprint.setActiveEdition(1);
        vm.stopPrank();

        // 複数ユーザーによる大量ミント実行
        uint256[] memory mintQuantities = new uint256[](3);
        mintQuantities[0] = 25; // user1: 最大制限
        mintQuantities[1] = 25; // user2: 最大制限  
        mintQuantities[2] = 25; // このコントラクト: 最大制限

        uint256[] memory gasUsages = new uint256[](3);

        // user1のミント
        uint256 gasStart = gasleft();
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(user1, mintQuantities[0]);
        gasUsages[0] = gasStart - gasleft();

        // user2のミント
        gasStart = gasleft();
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(user2, mintQuantities[1]);
        gasUsages[1] = gasStart - gasleft();

        // このコントラクトのミント
        gasStart = gasleft();
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(address(this), mintQuantities[2]);
        gasUsages[2] = gasStart - gasleft();

        // パフォーマンス分析
        uint256 totalMinted = mintQuantities[0] + mintQuantities[1] + mintQuantities[2];
        uint256 totalGas = gasUsages[0] + gasUsages[1] + gasUsages[2];
        
        console.log("User1 mint: %d NFTs, Gas: %d", mintQuantities[0], gasUsages[0]);
        console.log("User2 mint: %d NFTs, Gas: %d", mintQuantities[1], gasUsages[1]);
        console.log("Contract mint: %d NFTs, Gas: %d", mintQuantities[2], gasUsages[2]);
        console.log("Total minted: %d NFTs, Total Gas: %d", totalMinted, totalGas);
        console.log("Average Gas per NFT: %d", totalGas / totalMinted);

        // 検証
        assertEq(imprint.totalSupply(), totalMinted, "Total mint count incorrect");
        assertEq(imprint.balanceOf(user1), mintQuantities[0], "user1 balance incorrect");
        assertEq(imprint.balanceOf(user2), mintQuantities[1], "user2 balance incorrect");
        assertEq(imprint.balanceOf(address(this)), mintQuantities[2], "Contract balance incorrect");

        // 効率性確認（1NFTあたり15万ガス未満）
        assertTrue(totalGas / totalMinted < 150000, "Mint efficiency low");

        console.log(" High Volume Simultaneous Minting Test SUCCESS");
    }

    /*──────────── ヘルパー関数 ────────────*/
    
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
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        
        return string(buffer);
    }
}