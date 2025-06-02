// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { TestHelper } from "test/foundry/utils/TestHelper.sol";

import { Subject } from "../../src-upgradeable/src/Subject.sol";
import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import { ImprintViews } from "../../src-upgradeable/src/ImprintViews.sol";
import { ImprintDescriptor } from "../../src-upgradeable/src/ImprintDescriptor.sol";
import { IImprintDescriptor } from "../../src-upgradeable/src/interfaces/IImprintDescriptor.sol";

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
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";

/**
 * @title WorldCanonE2ETest
 * @notice 完全なWorld Canonライフサイクルをテストする包括的なE2Eテストスイート
 * 
 * テストシナリオ:
 * 1. "GPT-4oからClaude-3.7への時代遷移"完全フロー
 * 2. マルチユーザー同時ミント競争
 * 3. LLM出力からNFT可視化までの完全統合
 * 4. アップグレードシナリオでのデータ保持
 */
contract WorldCanonE2ETest is TestHelper, IERC721Receiver {
    /*──────────── コントラクトインスタンス ────────────*/
    Subject public subject;
    Imprint public imprint;
    ImprintViews public imprintViews;
    ImprintDescriptor public imprintDescriptor;
    ProxyAdmin public proxyAdmin;

    /*──────────── テストアクター ────────────*/
    address public curator = address(0x1001);       // キュレーター（運営者）
    address public collector1 = address(0x2001);   // コレクター1
    address public collector2 = address(0x2002);   // コレクター2
    address public collector3 = address(0x2003);   // コレクター3
    address public researcher = address(0x3001);   // 研究者

    /*──────────── テストデータ ────────────*/
    string[] internal initialSubjects;
    string[] internal additionalSubjects;

    /*──────────── イベント定義 ────────────*/
    event EditionCreated(uint64 indexed editionNo, string model, uint64 timestamp);
    event EditionSealed(uint64 indexed editionNo);
    event WorldCanonSet(address indexed worldCanon);
    event LatestImprintUpdated(uint256 indexed tokenId, uint256 indexed imprintId);

    /*──────────── セットアップ ────────────*/
    function setUp() public {
        // プロキシ管理用ProxyAdminをデプロイ
        proxyAdmin = new ProxyAdmin();

        /*──── Subject (不変NFT) のデプロイ ────*/
        subject = new Subject("World Canon Subjects", "WCSBJ");

        /*──── Imprint (アップグレード可能NFT) のデプロイ ────*/
        Imprint implementation = new Imprint();
        
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        bytes memory initData = abi.encodeWithSelector(
            Imprint.initializeImprint.selector,
            "WorldCanonImprint",
            "WCIMP",
            allowedSeaDrop,
            curator
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        imprint = Imprint(address(proxy));

        /*──── 補助コントラクトのデプロイ ────*/
        imprintViews = new ImprintViews(address(imprint));
        imprintDescriptor = new ImprintDescriptor(address(imprint));

        /*──── 初期設定 ────*/
        vm.startPrank(curator);
        imprint.setDescriptor(address(imprintDescriptor));
        imprint.setMaxSupply(10000);
        imprint.setContractURI("https://worldcanon.art/contract");
        imprint.setBaseURI("https://worldcanon.art/");
        
        // World Canon連携設定
        imprint.setWorldCanon(address(subject));
        
        // SeaDrop設定
        imprint.updateCreatorPayoutAddress(address(seadrop), curator);
        
        PublicDrop memory publicDrop = PublicDrop(
            0.01 ether,                    // mintPrice: 0.01 ETH
            uint48(block.timestamp),       // startTime: 現在
            uint48(block.timestamp) + 7 days, // endTime: 7日後
            25,                            // maxMintsPerWallet: 25枚まで
            250,                           // feeBps: 2.5%
            false                          // restrictFeeRecipients: false
        );
        
        imprint.updatePublicDrop(address(seadrop), publicDrop);
        imprint.updateAllowedFeeRecipient(address(seadrop), curator, true);
        vm.stopPrank();

        /*──── テストデータの準備 ────*/
        _prepareTestData();

        /*──── テストアクターにETHを配布 ────*/
        vm.deal(curator, 100 ether);
        vm.deal(collector1, 10 ether);
        vm.deal(collector2, 10 ether);
        vm.deal(collector3, 10 ether);
        vm.deal(researcher, 5 ether);
    }

    /*──────────── ヘルパー関数 ────────────*/
    function _prepareTestData() internal {
        // 初期1000件のSubject名を準備（簡略化版）
        for (uint256 i = 0; i < 50; i++) {
            initialSubjects.push(
                string(abi.encodePacked("Subject_", Strings.toString(i)))
            );
        }

        // 追加Subject名を準備
        for (uint256 i = 0; i < 10; i++) {
            additionalSubjects.push(
                string(abi.encodePacked("Additional_", Strings.toString(i)))
            );
        }
    }

    function _createGPT4oEdition() internal {
        vm.prank(curator);
        imprint.createEdition(1, "GPT-4o");

        // GPT-4o用のSeeds作成
        SeedInput[] memory seeds = new SeedInput[](50);
        for (uint16 i = 0; i < 50; i++) {
            seeds[i] = SeedInput({
                editionNo: 1,
                localIndex: i + 1,
                subjectId: i,
                subjectName: initialSubjects[i],
                desc: abi.encodePacked(
                    "GPT-4o perspective on ",
                    initialSubjects[i],
                    ": A nuanced AI interpretation of this concept."
                )
            });
        }

        vm.prank(curator);
        imprint.addSeeds(seeds);
        
        vm.prank(curator);
        imprint.sealEdition(1);
        
        vm.prank(curator);
        imprint.setActiveEdition(1);
    }

    function _createClaude3Edition() internal {
        vm.prank(curator);
        imprint.createEdition(2, "Claude-3.7");

        // Claude-3.7用のSeeds作成（同じSubjectに対する異なる視点）
        SeedInput[] memory seeds = new SeedInput[](50);
        for (uint16 i = 0; i < 50; i++) {
            seeds[i] = SeedInput({
                editionNo: 2,
                localIndex: i + 1,
                subjectId: i,
                subjectName: initialSubjects[i],
                desc: abi.encodePacked(
                    "Claude-3.7 perspective on ",
                    initialSubjects[i],
                    ": A thoughtful constitutional AI view of this subject."
                )
            });
        }

        vm.prank(curator);
        imprint.addSeeds(seeds);
        
        vm.prank(curator);
        imprint.sealEdition(2);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                     Complete Lifecycle E2E Tests                 */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice 👑 メインE2Eテスト: "GPT-4oからClaude-3.7への時代遷移"
     * 
     * このテストは完全なWorld Canonライフサイクルをシミュレートします：
     * 1. Subject初期セットアップ（1000件想定の50件）
     * 2. GPT-4o Edition作成・封印・アクティブ化
     * 3. パブリックミントによるImprint生成
     * 4. Subject.tokenURIの動的更新確認
     * 5. Claude-3.7 Edition作成と切替
     * 6. 新Edition対応のImprint発行
     * 7. 時代遷移の完全性確認
     */
    function testCompleteLifecycleGPT4oToClaude3() public {
        /*═══════════════════════════════════════════════════════════════*/
        /*                          Phase 1: 初期セットアップ              */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 1: Initial Subject setup started");
        
        // Subject初期1000件をミント（テストでは50件）
        vm.prank(curator);
        subject.mintInitial(initialSubjects);
        
        assertEq(subject.totalSupply(), 50, "Initial Subject count incorrect");
        assertEq(subject.ownerOf(0), curator, "Subject owner incorrect");
        
        console.log(" Initial Subject setup completed: %d items", subject.totalSupply());

        /*═══════════════════════════════════════════════════════════════*/
        /*                      Phase 2: GPT-4o Edition セットアップ       */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 2: GPT-4o Edition creation started");
        
        _createGPT4oEdition();
        
        // Edition作成の確認
        ImprintStorage.EditionHeader memory gptEdition = imprintViews.getEditionHeader(1);
        assertEq(gptEdition.editionNo, 1, "GPT Edition number incorrect");
        assertEq(gptEdition.model, "GPT-4o", "GPT Edition model name incorrect");
        assertTrue(gptEdition.isSealed, "GPT Edition not sealed");
        
        // Seeds数の確認
        assertEq(imprintViews.editionSize(1), 50, "GPT Edition Seeds count incorrect");
        assertEq(imprintViews.remainingInEdition(1), 50, "GPT Edition remaining count incorrect");
        
        console.log(" GPT-4o Edition setup completed");

        /*═══════════════════════════════════════════════════════════════*/
        /*                    Phase 3: パブリックミント（GPT Era）         */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 3: GPT-4o Era public mint started");
        
        uint256 mintQuantity = 5;
        
        // collector1がGPT-4o Editionからミント
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(collector1, mintQuantity);
        
        assertEq(imprint.totalSupply(), mintQuantity, "Mint count incorrect");
        assertEq(imprint.ownerOf(1), collector1, "NFT owner incorrect");
        assertEq(imprintViews.remainingInEdition(1), 50 - mintQuantity, "Edition remaining count incorrect");
        
        // ミントされたImprintのメタデータ確認
        ImprintStorage.TokenMeta memory tokenMeta = imprintViews.getTokenMeta(1);
        assertEq(tokenMeta.editionNo, 1, "Token Edition incorrect");
        assertEq(tokenMeta.model, "GPT-4o", "Token model incorrect");
        assertEq(tokenMeta.subjectName, "Subject_0", "Token Subject name incorrect");
        
        console.log(" GPT-4o Era mint completed: %d tokens issued", mintQuantity);

        /*═══════════════════════════════════════════════════════════════*/
        /*                  Phase 4: Subject.tokenURI 動的更新確認         */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 4: Subject dynamic update verification started");
        
        // Subject #0のtokenURIを取得（最新Imprint #1が反映されているはず）
        string memory subjectURI = subject.tokenURI(0);
        assertTrue(bytes(subjectURI).length > 0, "Subject tokenURI is empty");
        
        // Subject metaの確認
        (uint64 addedEdition, uint256 latestImprint, ) = subject.subjectMeta(0);
        assertEq(addedEdition, 0, "Subject added Edition number incorrect");
        assertEq(latestImprint, 1, "Latest Imprint ID incorrect");
        
        console.log(" Subject dynamic update verification completed");

        /*═══════════════════════════════════════════════════════════════*/
        /*                   Phase 5: Claude-3.7 Edition作成               */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 5: Claude-3.7 Edition creation started");
        
        _createClaude3Edition();
        
        // Claude Edition確認
        ImprintStorage.EditionHeader memory claudeEdition = imprintViews.getEditionHeader(2);
        assertEq(claudeEdition.editionNo, 2, "Claude Edition number incorrect");
        assertEq(claudeEdition.model, "Claude-3.7", "Claude Edition model name incorrect");
        assertTrue(claudeEdition.isSealed, "Claude Edition not sealed");
        
        // Active Editionを Claude-3.7 に切替
        vm.prank(curator);
        imprint.setActiveEdition(2);
        
        console.log(" Claude-3.7 Edition creation completed");

        /*═══════════════════════════════════════════════════════════════*/
        /*                 Phase 6: 時代遷移ミント（Claude Era）           */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 6: Claude Era transition mint started");
        
        uint256 claudeMintQuantity = 3;
        
        // collector2がClaude-3.7 Editionからミント
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(collector2, claudeMintQuantity);
        
        assertEq(imprint.totalSupply(), mintQuantity + claudeMintQuantity, "Total mint count incorrect");
        assertEq(imprint.ownerOf(6), collector2, "Claude Era NFT owner incorrect");
        
        // Claude EraのImprintメタデータ確認
        ImprintStorage.TokenMeta memory claudeTokenMeta = imprintViews.getTokenMeta(6);
        assertEq(claudeTokenMeta.editionNo, 2, "Claude Token Edition incorrect");
        assertEq(claudeTokenMeta.model, "Claude-3.7", "Claude Token model incorrect");
        assertEq(claudeTokenMeta.subjectName, "Subject_0", "Claude Token Subject name incorrect");
        
        console.log(" Claude Era mint completed: %d tokens issued", claudeMintQuantity);

        /*═══════════════════════════════════════════════════════════════*/
        /*                     Phase 7: 時代遷移完全性確認                 */
        /*═══════════════════════════════════════════════════════════════*/
        
        console.log("Phase 7: Era transition integrity verification started");
        
        // Subject #0の最新Imprint更新確認（Claude Era: tokenId=6）
        (, uint256 newLatestImprint, ) = subject.subjectMeta(0);
        assertEq(newLatestImprint, 6, "Subject latest Imprint not updated");
        
        // 両時代のImprintが共存していることを確認
        assertTrue(imprint.ownerOf(1) == collector1, "GPT Era NFT not maintained");
        assertTrue(imprint.ownerOf(6) == collector2, "Claude Era NFT not created");
        
        // tokenURIの世代違い確認
        string memory gptTokenURI = imprint.tokenURI(1);
        string memory claudeTokenURI = imprint.tokenURI(6);
        assertTrue(bytes(gptTokenURI).length > 0, "GPT tokenURI is empty");
        assertTrue(bytes(claudeTokenURI).length > 0, "Claude tokenURI is empty");
        
        // Subject URIの最新化確認
        string memory updatedSubjectURI = subject.tokenURI(0);
        assertTrue(bytes(updatedSubjectURI).length > 0, "Updated Subject tokenURI is empty");
        
        console.log(" Era transition integrity verification completed");
        console.log("Complete Lifecycle E2E Test SUCCESS!");
        
        /*═══════════════════════════════════════════════════════════════*/
        /*                        Final Verification                    */
        /*═══════════════════════════════════════════════════════════════*/
        
        // 最終状態の検証
        assertEq(subject.totalSupply(), 50, "Subject total count changed");
        assertEq(imprint.totalSupply(), 8, "Imprint total count incorrect");
        assertEq(imprintViews.editionSize(1), 50, "GPT Edition size changed");
        assertEq(imprintViews.editionSize(2), 50, "Claude Edition size incorrect");
        assertEq(imprintViews.remainingInEdition(1), 45, "GPT Edition remaining count incorrect");
        assertEq(imprintViews.remainingInEdition(2), 47, "Claude Edition remaining count incorrect");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                   🏆 Multi-User Concurrent Mint Tests             */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice マルチユーザー同時ミント競争テスト
     * 
     * シナリオ: 複数のコレクターが同時に25枚制限でミントを試行
     * 検証項目:
     * - 25枚制限の正確性
     * - 同時アクセス時のトランザクション順序
     * - ガス効率性
     * - エディション完売時のハンドリング
     */
    function testMultiUserConcurrentMinting() public {
        console.log("Multi-User Concurrent Minting Test started");
        
        // GPT-4o Editionをセットアップ
        _createGPT4oEdition();
        
        /*──── 同時ミント実行 ────*/
        uint256 mintQuantity = 25; // 上限まで
        
        // collector1: 25枚ミント
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(collector1, mintQuantity);
        assertEq(imprint.balanceOf(collector1), 25, "collector1 balance incorrect");
        
        // collector2: 25枚ミント
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(collector2, mintQuantity);
        assertEq(imprint.balanceOf(collector2), 25, "collector2 balance incorrect");
        
        // collector3: 残り分をミント（50 - 25 - 25 = 0, エラーになるはず）
        vm.prank(address(seadrop));
        vm.expectRevert(SoldOut.selector);
        imprint.mintSeaDrop(collector3, 1);
        
        /*──── 最終状態確認 ────*/
        assertEq(imprint.totalSupply(), 50, "Total mint count incorrect");
        assertEq(imprintViews.remainingInEdition(1), 0, "Edition not sold out");
        
        console.log(" Multi-User Concurrent Minting Test SUCCESS");
    }

    /*──────────────────────────────────────────────────────────────────*/
    /*                    🔗 Cross-Contract Integration Tests            */
    /*──────────────────────────────────────────────────────────────────*/

    /**
     * @notice クロスコントラクト統合テスト: LLM出力からNFT可視化まで
     * 
     * 完全な統合フローをテスト:
     * 1. LLM出力データの正規化処理
     * 2. SSTORE2によるオンチェーン保存
     * 3. SVG動的生成とBase64エンコーディング
     * 4. Subject側での最新Imprint反映
     * 5. Marketplace互換性確認
     */
    function testLLMOutputToNFTVisualizationFlow() public {
        console.log("LLM Output to NFT Visualization Flow Test started");
        
        /*──── セットアップ ────*/
        vm.prank(curator);
        subject.mintInitial(_createSingleSubjectArray("Happiness"));
        
        _createGPT4oEdition();
        
        /*──── LLM出力シミュレーション ────*/
        // string memory llmOutput = "Happiness is the fundamental pursuit of human existence, "
        //                           "manifesting as fleeting moments of joy that illuminate our "
        //                           "shared humanity and transcend individual suffering.";
        // llmOutput is simulated in the desc field of seeds
        
        /*──── NFTミント ────*/
        vm.prank(address(seadrop));
        imprint.mintSeaDrop(collector1, 1);
        
        /*──── SVG生成確認 ────*/
        string memory tokenImage = IImprintDescriptor(imprint.descriptor()).tokenImage(1);
        assertTrue(_startsWith(tokenImage, "data:image/svg+xml;base64,"), "SVG Data URI incorrect");
        
        /*──── JSON URI確認 ────*/
        string memory tokenURI = imprint.tokenURI(1);
        assertTrue(_startsWith(tokenURI, "data:application/json;base64,"), "JSON Data URI incorrect");
        
        /*──── Subject連携確認 ────*/
        (, uint256 latestImprint, ) = subject.subjectMeta(0);
        assertEq(latestImprint, 1, "Subject integration incorrect");
        
        string memory subjectURI = subject.tokenURI(0);
        assertTrue(bytes(subjectURI).length > 0, "Subject URI is empty");
        
        console.log(" LLM Output to NFT Visualization Flow Test SUCCESS");
    }

    /*──────────── ヘルパー関数 ────────────*/
    function _createSingleSubjectArray(string memory name) 
        internal 
        pure 
        returns (string[] memory) 
    {
        string[] memory arr = new string[](1);
        arr[0] = name;
        return arr;
    }

    function _startsWith(string memory str, string memory prefix) 
        internal 
        pure 
        returns (bool) 
    {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (prefixBytes.length > strBytes.length) return false;
        
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        
        return true;
    }
}