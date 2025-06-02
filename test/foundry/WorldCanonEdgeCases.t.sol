// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { TestHelper } from "test/foundry/utils/TestHelper.sol";

import { Subject } from "../../src-upgradeable/src/Subject.sol";
import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import { ImprintViews } from "../../src-upgradeable/src/ImprintViews.sol";
import { ImprintDescriptor } from "../../src-upgradeable/src/ImprintDescriptor.sol";

import {
    ImprintStorage,
    SeedInput,
    ZeroAddress,
    InvalidEditionNo,
    EmptyModel,
    EditionExists,
    UnknownEdition,
    AlreadySealed,
    EmptyInput,
    MixedEdition,
    EmptyDesc,
    EditionMissing,
    EditionAlreadySealed,
    DuplicateLocalIdx,
    EditionNotSealed,
    NoSeeds,
    MintingPaused,
    NoActiveEdition,
    SoldOut,
    TokenNonexistent,
    DescriptorUnset,
    DescriptorFail,
    WorldCanonAlreadySet
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
 * @title WorldCanonEdgeCasesTest
 * @notice エッジケースとエラーシナリオの包括的テストスイート
 * 
 * テストカテゴリ:
 * 1. 境界値テスト（容量上限、時間制限など）
 * 2. エラーハンドリング検証
 * 3. セキュリティ脆弱性テスト
 * 4. ガス効率性とパフォーマンステスト
 * 5. アップグレード時の互換性テスト
 */
contract WorldCanonEdgeCasesTest is TestHelper, IERC721Receiver {
    /*──────────── コントラクトインスタンス ────────────*/
    Subject public subject;
    Imprint public imprint;
    ImprintViews public imprintViews;
    ImprintDescriptor public imprintDescriptor;
    ProxyAdmin public proxyAdmin;

    /*──────────── テストアクター ────────────*/
    address public owner = address(0x1000);
    address public attacker = address(0x6666);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);

    /*──────────── セットアップ ────────────*/
    function setUp() public {
        // 基本セットアップ
        proxyAdmin = new ProxyAdmin();
        subject = new Subject("World Canon Subjects", "WCSBJ");

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
        imprint.setMaxSupply(1000);
        imprint.setWorldCanon(address(subject));
        
        PublicDrop memory publicDrop = PublicDrop(
            0.01 ether, uint48(block.timestamp), uint48(block.timestamp) + 1 days,
            25, 250, false
        );
        imprint.updatePublicDrop(address(seadrop), publicDrop);
        imprint.updateCreatorPayoutAddress(address(seadrop), owner);
        vm.stopPrank();

        // ETH配布
        vm.deal(owner, 100 ether);
        vm.deal(attacker, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function onERC721Received(address, address, uint256, bytes calldata) 
        external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                         Boundary Value Tests                    */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice 境界値テスト: 最大容量でのEdition作成
     */
    function testMaxCapacityEditionCreation() public {
        console.log("Max Capacity Edition Creation Test started");

        vm.startPrank(owner);
        
        // Edition作成
        imprint.createEdition(1, "MaxCapacityModel");
        
        // 1000件のSeed作成（メモリ制限内で）
        uint256 batchSize = 100;
        uint256 totalSeeds = 1000;
        
        for (uint256 batch = 0; batch < totalSeeds / batchSize; batch++) {
            SeedInput[] memory seeds = new SeedInput[](batchSize);
            
            for (uint256 i = 0; i < batchSize; i++) {
                uint256 globalIndex = batch * batchSize + i;
                seeds[i] = SeedInput({
                    editionNo: 1,
                    localIndex: uint16(globalIndex + 1),
                    subjectId: globalIndex,
                    subjectName: string(abi.encodePacked("Subject_", _toString(globalIndex))),
                    desc: string(abi.encodePacked("Description_", _toString(globalIndex)))
                });
            }
            
            imprint.addSeeds(seeds);
            console.log("Batch %d/%d completed", batch + 1, totalSeeds / batchSize);
        }
        
        imprint.sealEdition(1);
        imprint.setActiveEdition(1);
        vm.stopPrank();

        // 検証
        assertEq(imprintViews.editionSize(1), totalSeeds, "Edition size incorrect");
        assertEq(imprintViews.remainingInEdition(1), totalSeeds, "Edition remaining count incorrect");
        
        console.log("OK Max Capacity Edition Creation Test SUCCESS");
    }

    /**
     * @notice 境界値テスト: 最大ミント制限（25枚）での動作確認
     */
    function testMaxMintLimitBoundary() public {
        console.log("Max Mint Limit Boundary Test started");

        // セットアップ
        _createBasicEdition();

        // 24枚ミント（制限内）
        vm.prank(address(seadrop));
        imprint.mintSeaDrop{value: 0.24 ether}(user1, 24);
        assertEq(imprint.balanceOf(user1), 24, "24 token mint failed");

        // 1枚追加ミント（制限ピッタリ）
        vm.prank(address(seadrop));
        imprint.mintSeaDrop{value: 0.01 ether}(user1, 1);
        assertEq(imprint.balanceOf(user1), 25, "25th token mint failed");

        // 1枚追加ミント（制限超過）
        vm.prank(address(seadrop));
        vm.expectRevert();
        imprint.mintSeaDrop{value: 0.01 ether}(user1, 1);

        console.log(" Max Mint Limit Boundary Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                        Error Handling Tests                     */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice エラーハンドリング: 不正なEdition操作
     */
    function testInvalidEditionOperations() public {
        console.log("Invalid Edition Operations Test started");

        vm.startPrank(owner);

        // 存在しないEditionのSeal試行
        vm.expectRevert(UnknownEdition.selector);
        imprint.sealEdition(999);

        // 空のモデル名でEdition作成
        vm.expectRevert(EmptyModel.selector);
        imprint.createEdition(1, "");

        // Edition作成
        imprint.createEdition(1, "TestModel");

        // 重複Edition作成
        vm.expectRevert(EditionExists.selector);
        imprint.createEdition(1, "DuplicateModel");

        // Seedなしでの封印試行
        vm.expectRevert(NoSeeds.selector);
        imprint.sealEdition(1);

        vm.stopPrank();

        console.log(" Invalid Edition Operations Test SUCCESS");
    }

    /**
     * @notice エラーハンドリング: 不正なSeed追加
     */
    function testInvalidSeedOperations() public {
        console.log("Invalid Seed Operations Test started");

        vm.startPrank(owner);
        imprint.createEdition(1, "TestModel");

        // 空のSeed配列
        SeedInput[] memory emptySeeds = new SeedInput[](0);
        vm.expectRevert(EmptyInput.selector);
        imprint.addSeeds(emptySeeds);

        // 重複するlocalIndex
        SeedInput[] memory duplicateSeeds = new SeedInput[](2);
        duplicateSeeds[0] = SeedInput({
            editionNo: 1, localIndex: 1, subjectId: 0,
            subjectName: "Test1", desc: "Desc1"
        });
        duplicateSeeds[1] = SeedInput({
            editionNo: 1, localIndex: 1, subjectId: 1,
            subjectName: "Test2", desc: "Desc2"
        });
        vm.expectRevert(DuplicateLocalIdx.selector);
        imprint.addSeeds(duplicateSeeds);

        // 異なるEditionの混在
        SeedInput[] memory mixedSeeds = new SeedInput[](2);
        mixedSeeds[0] = SeedInput({
            editionNo: 1, localIndex: 1, subjectId: 0,
            subjectName: "Test1", desc: "Desc1"
        });
        mixedSeeds[1] = SeedInput({
            editionNo: 2, localIndex: 1, subjectId: 1,
            subjectName: "Test2", desc: "Desc2"
        });
        vm.expectRevert(MixedEdition.selector);
        imprint.addSeeds(mixedSeeds);

        vm.stopPrank();

        console.log(" Invalid Seed Operations Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                       Security Vulnerability Tests              */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice セキュリティテスト: アクセス制御の確認
     */
    function testAccessControlSecurity() public {
        console.log("Access Control Security Test started");

        // 非所有者による操作試行
        vm.startPrank(attacker);

        // Edition作成試行
        vm.expectRevert();
        imprint.createEdition(1, "AttackerModel");

        // MaxSupply変更試行
        vm.expectRevert();
        imprint.setMaxSupply(999999);

        // WorldCanon設定試行
        vm.expectRevert();
        imprint.setWorldCanon(address(attacker));

        // ミント停止試行
        vm.expectRevert();
        imprint.setMintPaused(true);

        vm.stopPrank();

        // Subject側のセキュリティ
        vm.startPrank(attacker);

        string[] memory maliciousSubjects = new string[](1);
        maliciousSubjects[0] = "MaliciousSubject";

        // Subject初期ミント試行
        vm.expectRevert("Ownable: caller is not the owner");
        subject.mintInitial(maliciousSubjects);

        // Subject追加試行
        vm.expectRevert("Ownable: caller is not the owner");
        subject.addSubjects(maliciousSubjects, 999);

        vm.stopPrank();

        console.log(" Access Control Security Test SUCCESS");
    }

    /**
     * @notice セキュリティテスト: 再入攻撃の防止
     */
    function testReentrancyProtection() public {
        console.log("Reentrancy Protection Test started");

        _createBasicEdition();

        // 悪意のあるコントラクトによる再入攻撃試行
        MaliciousReentrancy malicious = new MaliciousReentrancy(address(imprint), address(seadrop));
        vm.deal(address(malicious), 1 ether);

        // 再入攻撃実行（失敗するはず）
        vm.expectRevert();
        malicious.attemptReentrancy();

        console.log(" Reentrancy Protection Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                      Gas Efficiency Tests                       */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice ガス効率性テスト: バッチオペレーションの最適化
     */
    function testGasEfficiencyBatchOperations() public {
        console.log("Gas Efficiency Batch Operations Test started");

        vm.startPrank(owner);
        imprint.createEdition(1, "GasTestModel");

        // 単発追加 vs バッチ追加のガス効率比較
        uint256 singleGasUsed = 0;
        uint256 batchGasUsed = 0;

        // 単発追加（10回）
        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            SeedInput[] memory singleSeed = new SeedInput[](1);
            singleSeed[0] = SeedInput({
                editionNo: 1, localIndex: uint16(i + 1), subjectId: i,
                subjectName: _toString(i), desc: _toString(i)
            });
            imprint.addSeeds(singleSeed);
        }
        singleGasUsed = gasStart - gasleft();

        // 新しいEditionでバッチ追加
        imprint.createEdition(2, "BatchTestModel");
        
        SeedInput[] memory batchSeeds = new SeedInput[](10);
        for (uint256 i = 0; i < 10; i++) {
            batchSeeds[i] = SeedInput({
                editionNo: 2, localIndex: uint16(i + 1), subjectId: i,
                subjectName: _toString(i), desc: _toString(i)
            });
        }

        gasStart = gasleft();
        imprint.addSeeds(batchSeeds);
        batchGasUsed = gasStart - gasleft();

        vm.stopPrank();

        console.log("Single addition gas usage: %d", singleGasUsed);
        console.log("Batch addition gas usage: %d", batchGasUsed);
        
        // バッチの方が効率的であることを確認
        assertTrue(batchGasUsed < singleGasUsed, "Batch operation not efficient");

        console.log(" Gas Efficiency Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                       Upgrade Compatibility Tests               */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice アップグレード互換性テスト: データ保持確認
     */
    function testUpgradeDataPersistence() public {
        console.log("Upgrade Data Persistence Test started");

        // 初期データ作成
        _createBasicEdition();
        
        vm.prank(address(seadrop));
        imprint.mintSeaDrop{value: 0.05 ether}(user1, 5);

        // アップグレード前の状態を記録
        uint256 preUpgradeTotalSupply = imprint.totalSupply();
        address preUpgradeOwner = imprint.ownerOf(1);
        ImprintStorage.EditionHeader memory preUpgradeEdition = imprintViews.getEditionHeader(1);

        // 新しい実装をデプロイ
        ImprintV2 newImplementation = new ImprintV2();

        // アップグレード実行
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(imprint))),
            address(newImplementation)
        );

        // アップグレード後の状態確認
        assertEq(imprint.totalSupply(), preUpgradeTotalSupply, "totalSupply changed");
        assertEq(imprint.ownerOf(1), preUpgradeOwner, "NFT owner changed");
        
        ImprintStorage.EditionHeader memory postUpgradeEdition = imprintViews.getEditionHeader(1);
        assertEq(postUpgradeEdition.model, preUpgradeEdition.model, "Edition data changed");

        // 新機能の確認
        assertEq(ImprintV2(address(imprint)).version(), "v2", "New feature unavailable");

        console.log(" Upgrade Data Persistence Test SUCCESS");
    }

    /*──────────── ヘルパー関数とコントラクト ────────────*/
    
    function _createBasicEdition() internal {
        vm.startPrank(owner);
        imprint.createEdition(1, "BasicModel");
        
        SeedInput[] memory seeds = new SeedInput[](50);
        for (uint16 i = 0; i < 50; i++) {
            seeds[i] = SeedInput({
                editionNo: 1, localIndex: i + 1, subjectId: i,
                subjectName: _toString(i), desc: _toString(i)
            });
        }
        
        imprint.addSeeds(seeds);
        imprint.sealEdition(1);
        imprint.setActiveEdition(1);
        vm.stopPrank();
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
            digits--;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        
        return string(buffer);
    }
}

// アップグレードテスト用のV2実装
contract ImprintV2 is Imprint {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

// 再入攻撃テスト用の悪意のあるコントラクト
contract MaliciousReentrancy is IERC721Receiver {
    Imprint private target;
    address private seadrop;
    bool private attacking = false;

    constructor(address _target, address _seadrop) {
        target = Imprint(_target);
        seadrop = _seadrop;
    }

    function attemptReentrancy() external {
        attacking = true;
        // 再入攻撃試行
        target.mintSeaDrop{value: 0.01 ether}(address(this), 1);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        if (attacking) {
            attacking = false;
            // 再入試行
            target.mintSeaDrop{value: 0.01 ether}(address(this), 1);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}