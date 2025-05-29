// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Subject} from "../../src-upgradeable/src/Subject.sol";
import {LibNormalize} from "../../src-upgradeable/src/LibNormalize.sol";

using LibNormalize for string;


/*──── Minimal mock Imprint ────*/
contract MockImprint {
    function tokenImage(uint256) external pure returns (string memory) {
        return "mock://image";
    }
}

contract SubjectTest is Test {
    Subject subject;
    address alice = address(0xA);
    address bob   = address(0xB);

    /*── イベントを再宣言（テスト用） ──*/
    event LatestImprintUpdated(uint256 indexed tokenId, uint256 indexed imprintId);

    /*──────────── Helpers ────────────*/
    function _names1(string memory a) internal pure returns (string[] memory arr) {
        arr = new string[](1);
        arr[0] = a;
    }
    function _names2(string memory a, string memory b) internal pure returns (string[] memory arr) {
        arr = new string[](2);
        arr[0] = a;
        arr[1] = b;
    }
    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory A = bytes(s);
        bytes memory P = bytes(prefix);
        if (P.length > A.length) return false;
        for (uint256 i; i < P.length; ++i) if (A[i] != P[i]) return false;
        return true;
    }

    /*──────────── setUp ────────────*/
    function setUp() public {
        subject = new Subject("World Canon Subjects", "SUBJ");
    }

    /*──────────── Tests ────────────*/
    function testOwnerIsDeployer() public {
        assertEq(subject.owner(), address(this));
    }

    /* mintInitial */
    function testMintInitialByOwner() public {
        subject.mintInitial(_names2("Happiness", "Sorrow"));
        assertEq(subject.totalSupply(), 2);
        assertEq(subject.ownerOf(0), address(this));
    }

    function testMintInitialOnlyOnce() public {
        subject.mintInitial(_names1("Alpha"));
        vm.expectRevert("initialized");
        subject.mintInitial(_names1("Beta"));
    }

    function testMintInitialNonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        subject.mintInitial(_names1("Foo"));
    }

    /* addSubjects */
    function testAddSubjects() public {
        subject.mintInitial(_names1("Seed"));
        string[] memory more = _names2("Gamma", "Delta");
        subject.addSubjects(more, 42);
        assertEq(subject.totalSupply(), 3);
        (uint64 ed, , ) = subject.subjectMeta(2);
        assertEq(ed, 42);
    }

    function testAddSubjectsOnlyOwner() public {
        subject.mintInitial(_names1("Seed"));
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        subject.addSubjects(_names1("Y"), 1);
    }

    /* setLatest */
    function testSetLatestUpdatesMetaAndEmits() public {
        subject.mintInitial(_names1("Ocean"));
        vm.expectEmit(true, true, false, true);
        emit LatestImprintUpdated(0, 777);
        subject.setLatest(0, 777);
        (, uint256 latest, ) = subject.subjectMeta(0);
        assertEq(latest, 777);
    }

    function testSetLatestOnlyOwner() public {
        subject.mintInitial(_names1("Earth"));
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        subject.setLatest(0, 1);
    }

    /* setImprintContract */
    function testSetImprintContractOnlyOwner() public {
        MockImprint mock = new MockImprint();
        subject.setImprintContract(address(mock));
        assertEq(subject.imprintContract(), address(mock));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        subject.setImprintContract(address(0x1234));
    }

    /* tokenURI */
    function testTokenURIPaths() public {
        subject.mintInitial(_names1("Sky"));

        // placeholder
        string memory uri0 = subject.tokenURI(0);
        assertTrue(_startsWith(uri0, "data:application/json;base64,"));

        // imprint
        MockImprint mock = new MockImprint();
        subject.setImprintContract(address(mock));
        subject.setLatest(0, 99);
        string memory uri1 = subject.tokenURI(0);
        assertTrue(_startsWith(uri1, "data:application/json;base64,"));
    }

    /*───────────────────────────────────────────────────────────────*\
    |*                 ▼ sync to imprint test ▼                      *|
    \*───────────────────────────────────────────────────────────────*/

    /* syncFromImprint — 新規 Subject 自動生成 */
    function testSyncFromImprintCreatesSubject() public {
        // ① imprintContract セット
        MockImprint mock = new MockImprint();
        subject.setImprintContract(address(this)); // ← テストコントラクトを Imprint と見なす

        // ② まだ totalSupply==0
        assertEq(subject.totalSupply(), 0);

        // ③ sync 呼び出し（新しい subjectName）
        string memory name = "Happiness";
        subject.syncFromImprint(name, 11, 1_000);

        // ④ 自動生成を検証
        assertEq(subject.totalSupply(), 1);
        ( , uint256 latest, uint256 ts ) = subject.subjectMeta(0);
        assertEq(latest, 11);
        assertEq(ts,     1_000);

        // ⑤ 名前ハッシュが TokenId(+1) に紐付いていること
        // アプローチを変更: publicのgetSubjectIdByName関数が必要か、
        // またはマッピングへの直接アクセスはテストでは困難なので、
        // 同じ名前でもう一度syncFromImprintを呼び出して既存のIDが使われることを確認
        string memory sameName = "Happiness";
        uint256 prevSupply = subject.totalSupply();
        subject.syncFromImprint(sameName, 12, 2_000);
        assertEq(subject.totalSupply(), prevSupply); // 新しいSubjectは作成されない
        
        ( , uint256 latestAfter, uint256 tsAfter ) = subject.subjectMeta(0);
        assertEq(latestAfter, 12);
        assertEq(tsAfter, 2_000);
    }

    /* syncFromImprint — 既存 Subject の更新と timestamp 比較 */
    function testSyncFromImprintUpdatesOnlyNewer() public {
        // セットアップ: 初期ミントで tokenId 0 を作成
        subject.mintInitial(_names1("Ocean"));
        subject.setImprintContract(address(this));

        // 古い timestamp (500) で sync → 反映
        subject.syncFromImprint("Ocean", 21, 500);
        (, uint256 latestOld, uint256 tsOld) = subject.subjectMeta(0);
        assertEq(latestOld, 21);
        assertEq(tsOld,     500);

        // 更に古い timestamp (400) で sync → 無視
        subject.syncFromImprint("Ocean", 22, 400);
        (, uint256 latestStill, uint256 tsStill) = subject.subjectMeta(0);
        assertEq(latestStill, 21);
        assertEq(tsStill,     500);

        // 新しい timestamp (600) で sync → 上書き
        subject.syncFromImprint("Ocean", 23, 600);
        (, uint256 latestNew, uint256 tsNew) = subject.subjectMeta(0);
        assertEq(latestNew, 23);
        assertEq(tsNew,     600);
    }

    /* syncFromImprint — onlyImprint 修飾子 */
    function testSyncFromImprintOnlyImprint() public {
        subject.setImprintContract(address(0x1234));
        vm.expectRevert("onlyImprint");
        subject.syncFromImprint("X", 1, 100);
    }

    /* 名前正規化 & 重複ガード */
    function testDuplicateNameGuard() public {
        // mix 大文字・前後空白で同一視
        string[] memory alpha = _names1("  ALPHA ");
        subject.mintInitial(alpha);

        // 同義語「alpha」登録は revert
        vm.expectRevert("dup subject");
        subject.addSubjects(_names1("alpha"), 1);
    }

    /* tokenURI placeholder when imprintContract not set */
    function testTokenURIPlaceholderWhenNoImprintContract() public {
        subject.mintInitial(_names1("Sky"));
        // latestImprintId を >0 にする
        subject.setLatest(0, 999);

        // imprintContract は未設定 ⇒ placeholder 文字列（SVG data URL）を返す
        string memory uri = subject.tokenURI(0);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }
}