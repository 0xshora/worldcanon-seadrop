// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Subject} from "../../src-upgradeable/src/Subject.sol";

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
        (uint64 ed, ) = subject.subjectMeta(2);
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
        (, uint256 latest) = subject.subjectMeta(0);
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
}