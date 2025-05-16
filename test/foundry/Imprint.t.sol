// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TestHelper } from "test/foundry/utils/TestHelper.sol";

import { Imprint } from "../../src-upgradeable/src/Imprint.sol";
import { TransparentUpgradeableProxy } from
    "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from
    "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import { PublicDrop } from "../../src-upgradeable/src/lib/SeaDropStructsUpgradeable.sol";
import {
    IERC721Receiver
} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

contract ImprintV2 is Imprint {
    function version() external pure returns (string memory) {
        return "v2";
    }
}



contract ImprintTest is TestHelper, IERC721Receiver {
    Imprint imprint;
    ProxyAdmin proxyAdmin;
    address user = address(0x123);

    address[] allowedSeaDrop;

    function setUp() public {
        proxyAdmin = new ProxyAdmin();
        Imprint implementation = new Imprint();

        allowedSeaDrop    = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        bytes memory data = abi.encodeWithSelector(
            Imprint.initializeImprint.selector,
            "WorldCanonImprint",
            "WCIMP",
            allowedSeaDrop,
            address(this)
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(
                address(implementation),
                address(proxyAdmin),
                data
            );

        imprint = Imprint(address(proxy));

        imprint.setMaxSupply(1000);
        // imprint.updateCreatorPayoutAddress(seadrop, user);
        imprint.setContractURI("https://example.com/contract");
        imprint.setBaseURI("https://example.com/base");

        // Set the creator payout address.
        imprint.updateCreatorPayoutAddress(address(seadrop), creator);

        // Create the public drop stage.
        PublicDrop memory publicDrop = PublicDrop(
            0.1 ether, // mint price
            uint48(block.timestamp), // start time
            uint48(block.timestamp) + 100, // end time
            10, // max mints per wallet
            100, // fee (1%)
            false // if false, allow any fee recipient
        );

        // Set the public drop for the token contract.
        imprint.updatePublicDrop(address(seadrop), publicDrop);

        imprint.updateAllowedFeeRecipient(
            address(seadrop),
            address(5),
            true
        );
    }

    function testInitializeSvgPointers() public view {
        address prefixPtr = imprint.svgPrefixPtr();
        address suffixPtr = imprint.svgSuffixPtr();
        assertTrue(prefixPtr != address(0));
        assertTrue(suffixPtr != address(0));
    }

    function testInitializeImprint() public view {
        assertEq(imprint.name(), "WorldCanonImprint");
        assertEq(imprint.symbol(), "WCIMP");
        assertEq(imprint.totalSupply(), 0);
    }

    /* ------------------------------------------------------------------ */
    /*                        IERC721Receiver hook                        */
    /* ------------------------------------------------------------------ */
    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /* --------------------- Transparent Proxy 特有テスト ------------------- */

    /// admin はロジック関数を呼べない（fallback 分岐）
    function testAdminCannotFallback() public {
        vm.prank(address(proxyAdmin));
        vm.expectRevert(
            "TransparentUpgradeableProxy: admin cannot fallback to proxy target"
        );
        Imprint(address(imprint)).totalSupply();
    }

    /// non-owner は onlyOwner を実行できない
    function testOnlyOwnerGuard() public {
        vm.prank(user);
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")) );
        imprint.setMaxSupply(2000);
    }
    
    /* ----------------------------- UPGRADE TEST --------------------------- */

    /* ───────── upgrade 前後の state 保持 ───────── */
    function testUpgradeByAdmin() public {
        /* 0) 事前に 2 枚ミントして state を作る */
        vm.prank(allowedSeaDrop[0]);
        imprint.mintSeaDrop(address(this), 2);
        assertEq(imprint.totalSupply(), 2);

        /* 1) 新実装 */
        ImprintV2 newImpl = new ImprintV2();

        /* 2) 非 admin で失敗 */
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(imprint))),
            address(newImpl)
        );

        /* 3) admin で成功 */
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(imprint))),
            address(newImpl)
        );

        /* 4) state 保持 + 新機能 */
        assertEq(ImprintV2(address(imprint)).totalSupply(), 2);
        assertEq(ImprintV2(address(imprint)).version(), "v2");
    }





    // function testMintInitialSetsSubjectMeta() public {
    //     string[] memory names = new string[](3);
    //     names[0] = "One";
    //     names[1] = "Two";
    //     names[2] = "Three";
    //     imprint.mintInitial(names, 0);
    //     assertEq(imprint.totalSupply(), 3);
    //     for (uint256 i = 0; i < 3; i++) {
    //         (uint64 editionNo, uint256 latest) = imprint.subjectMeta(i);
    //         assertEq(editionNo, 0);
    //         assertEq(latest, 0);
    //     }
    // }

    // function testAddSubjectsSetsEditionHeader() public {
    //     string[] memory names = new string[](2);
    //     names[0] = "Alpha";
    //     names[1] = "Beta";
    //     vm.warp(1000);
    //     uint64 editionNo = 1;
    //     imprint.addSubjects(names, editionNo);
    //     assertEq(imprint.totalSupply(), 2);

    //     (uint64 ed, uint256 lat) = imprint.subjectMeta(0);
    //     assertEq(ed, editionNo);
    //     assertEq(lat, 0);

    //     (uint256 hdrNo, string memory model, uint64 ts, bool isSealed) = imprint.editionHeaders(editionNo);
    //     assertEq(hdrNo, editionNo);
    //     assertEq(ts, 1000);
    //     assertEq(model, "");
    //     assertFalse(isSealed);
    // }

    // function testSetLatestUpdatesLatestImprintId() public {
    //     string[] memory names = new string[](1);
    //     names[0] = "Zeta";
    //     imprint.mintInitial(names, 0);
    //     imprint.setLatest(0, 42);
    //     (, uint256 latest) = imprint.subjectMeta(0);
    //     assertEq(latest, 42);
    // }

    // function testOnlyOwnerReverts() public {
    //     string[] memory names = new string[](1);
    //     names[0] = "Gamma";
    //     vm.prank(user);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     imprint.mintInitial(names, 0);
    // }

    // /// @notice Only owner can add subjects
    // function testAddSubjectsRevertsForNonOwner() public {
    //     string[] memory names = new string[](1);
    //     names[0] = "Foo";
    //     vm.prank(user);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     imprint.addSubjects(names, 1);
    // }

    /// @notice Only owner can set latest imprint
    // function testSetLatestRevertsForNonOwner() public {
    //     vm.prank(user);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     imprint.setLatest(0, 1);
    // }

    // ===== SeaDrop integration tests =====
    function testMintSeaDropRevertsWhenNotAllowed() public {
        vm.expectRevert();
        vm.prank(user);
        imprint.mintSeaDrop(address(this), 1);
    }

    function testMintSeaDropAsAllowed() public {
        vm.prank(allowedSeaDrop[0]);                 // SeaDrop からの呼び出しを偽装
        imprint.mintSeaDrop(address(this), 2);       // 2 枚ミント（ID 1,2）
        assertEq(imprint.totalSupply(), 2);
        assertEq(imprint.ownerOf(1), address(this));
        assertEq(imprint.ownerOf(2), address(this));
    }

    function testUpdateAllowedSeaDropRevertsForNonOwner() public {
        address[] memory newAllowedSeaDrop = new address[](1);
        newAllowedSeaDrop[0] = address(0xCAFE);
        vm.prank(user);
        vm.expectRevert();
        imprint.updateAllowedSeaDrop(newAllowedSeaDrop);
    }

    function testUpdateAllowedSeaDrop() public {
        address newAllowed = address(0xCAFE);
        address[] memory newAllowedSeaDrop = new address[](1);
        newAllowedSeaDrop[0] = newAllowed;
        imprint.updateAllowedSeaDrop(newAllowedSeaDrop);
        // Old allowed should revert
        vm.expectRevert();
        vm.prank(allowedSeaDrop[0]);
        imprint.mintSeaDrop(address(this), 1);
        // New allowed should succeed
        vm.prank(newAllowed);
        imprint.mintSeaDrop(address(this), 3);
        assertEq(imprint.totalSupply(), 3);
        assertEq(imprint.ownerOf(1), address(this));
        assertEq(imprint.ownerOf(2), address(this));
        assertEq(imprint.ownerOf(3), address(this));
    }
}
