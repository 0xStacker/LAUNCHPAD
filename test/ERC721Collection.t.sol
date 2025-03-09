// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Drop} from "../src/ERC721Collection.sol";
import {IERC721Collection} from "../src/IERC721Collection.sol";

contract ERC721CollectionTest is Test {
    Drop public collection;
    address creator = address(123);
    bool lockedTillMintOut = true;
    uint256 public singleMintCost = 110;
    uint256 publicMintLimit = 2;
    uint256 salePrice = 200;
    IERC721Collection.Platform platform = IERC721Collection.Platform({
        salesFeeBps: 10_00, // 10% of sales fee
        feeReceipient: address(234), // fee receipient
        mintFee: 10
    });

    bytes32[] proof = [
        bytes32(0xad67874866783b4129c60d23995daac0c837c320b38a19d1915e7fa4586bcefc),
        bytes32(0xf0718c9b19326d1812c0d459d3507b9122280148d3f90f4f3c97c0e6a9c946e5)
    ];

    IERC721Collection.PublicMint public publicMintConfig =
        IERC721Collection.PublicMint({maxPerWallet: 2, startTime: 0, endTime: 100, price: 100});

    IERC721Collection.PresalePhaseIn public presalePhaseConfig1 = IERC721Collection.PresalePhaseIn({
        maxPerAddress: 2,
        name: "Test Phase",
        price: 50,
        startTime: 0,
        endTime: 100,
        merkleRoot: bytes32(0x9c8ddc6ab231bcd108eb0758933a2bb40bc8dad8fbae0261383da40014080906)
    });

    IERC721Collection.PresalePhaseIn public presalePhaseConfig2 = IERC721Collection.PresalePhaseIn({
        maxPerAddress: 2,
        name: "Test Phase 2",
        price: 150,
        startTime: 10,
        endTime: 50,
        merkleRoot: bytes32(0x9c8ddc6ab231bcd108eb0758933a2bb40bc8dad8fbae0261383da40014080906)
    });

    IERC721Collection.Collection collectionConfig1 = IERC721Collection.Collection({
        tradingLocked: true,
        revealed: false,
        maxSupply: 100,
        owner: creator,
        proceedCollector: address(0),
        royaltyReceipient: address(0),
        name: "Test Collection",
        symbol: "TST",
        baseURI: "https://example.com/",
        royaltyFeeBps: 500
    });

    function setUp() public {
        collection = new Drop(collectionConfig1, publicMintConfig, platform);
    }

    function _getOldData(address _minter)
        internal
        view
        returns (
            uint256 previousMinterNftBal,
            uint256 previousCreatorEthBal,
            uint256 previousPlatformEthBal,
            uint256 previousTotalMinted
        )
    {
        previousMinterNftBal = collection.balanceOf(address(_minter));
        previousTotalMinted = collection.totalMinted();
        previousCreatorEthBal = creator.balance;
        previousPlatformEthBal = platform.feeReceipient.balance;
        console.log("Creator previous balance: ", previousCreatorEthBal);
        console.log("Platform previous balance: ", previousPlatformEthBal);
    }

    function _verifyOldDataWithNew(
        address _minter,
        uint256 _prevMinterNftBal,
        uint256 _amount,
        uint256 _prevCreatorEthBal,
        uint256 _prevPlatformEthBal,
        uint256 _prevTotalMinted
    ) internal view {
        uint256 newMinterNftBal = collection.balanceOf(_minter);
        uint256 newCreatorEthBal = _prevCreatorEthBal
            + collection.computeShare(IERC721Collection.MintPhase.PUBLIC, _amount, 0, IERC721Collection.Payees.CREATOR);
        uint256 newPlatformEthBal = _prevPlatformEthBal
            + collection.computeShare(IERC721Collection.MintPhase.PUBLIC, _amount, 0, IERC721Collection.Payees.PLATFORM);

        console.log("Creator new balance: ", newCreatorEthBal);
        console.log("Platform new balance: ", newPlatformEthBal);
        assertEq(newMinterNftBal, _prevMinterNftBal + _amount);
        assertEq(collection.totalMinted(), _prevTotalMinted + _amount);
        assertEq(creator.balance, newCreatorEthBal);
        assertEq(platform.feeReceipient.balance, newPlatformEthBal);
    }

    function _mintPublic(Drop _collection, address _to, uint256 _amount, uint256 _value) internal {
        vm.prank(_to);
        _collection.mintPublic{value: _value}(_amount, address(_to));
    }

    function test_publicMint() public {
        address minter = address(456);
        deal(minter, 350);
        (
            uint256 previousMinterNftBal,
            uint256 previousCreatorEthBal,
            uint256 previousPlatformEthBal,
            uint256 previousTotalMinted
        ) = _getOldData(minter);
        _mintPublic(collection, minter, 1, singleMintCost);
        _verifyOldDataWithNew(
            minter, previousMinterNftBal, 1, previousCreatorEthBal, previousPlatformEthBal, previousTotalMinted
        );
    }

    function testRevertpublicMintLimit() public {
        address minter = address(456);
        deal(minter, 350);
        vm.expectRevert();
        _mintPublic(collection, minter, 3, singleMintCost * 3);
    }

    function test_mintMultiple() public {
        address minter = address(456);
        deal(minter, 350);
        (
            uint256 previousMinterNftBal,
            uint256 previousCreatorEthBal,
            uint256 previousPlatformEthBal,
            uint256 previousTotalMinted
        ) = _getOldData(minter);
        _mintPublic(collection, minter, 2, singleMintCost * 2);
        _verifyOldDataWithNew(
            minter, previousMinterNftBal, 2, previousCreatorEthBal, previousPlatformEthBal, previousTotalMinted
        );
    }

    function test_addPresale() public {
        uint256 startTimeInSec = 0;
        uint256 endTimeInSec = 100;
        vm.prank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        assertEq(collection.getPresaleConfig().length, 1);
        assertEq(collection.getPresaleConfig()[0].maxPerAddress, 2);
        assertEq(collection.getPresaleConfig()[0].name, "Test Phase");
        assertEq(collection.getPresaleConfig()[0].price, 50);
        assertEq(collection.getPresaleConfig()[0].startTime, block.timestamp + startTimeInSec);
        assertEq(collection.getPresaleConfig()[0].endTime, block.timestamp + endTimeInSec);
    }

    function testRevert_WhenPresaleLimitReached() public {
        uint256 startTimeInSec = 0;
        uint256 endTimeInSec = 100;
        IERC721Collection.PresalePhaseIn memory phase = IERC721Collection.PresalePhaseIn({
            maxPerAddress: 2,
            name: "Test Phase",
            price: 100,
            startTime: startTimeInSec,
            endTime: endTimeInSec,
            merkleRoot: bytes32(0)
        });
        vm.startPrank(creator);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        vm.expectRevert();
        collection.addPresalePhase(phase);
        vm.stopPrank();
    }

    function testAirdrop() public {
        vm.prank(creator);
        collection.airdrop(address(234), 3);
        assertEq(collection.balanceOf(address(234)), 3);
        assertEq(collection.totalMinted(), 3);
    }

    function test_batchAirdrop() public {
        address[] memory addresses = new address[](3);
        addresses[0] = address(234);
        addresses[1] = address(345);
        addresses[2] = address(456);
        vm.prank(creator);
        collection.batchAirdrop(addresses, 1);
        assertEq(collection.balanceOf(address(234)), 1);
        assertEq(collection.balanceOf(address(345)), 1);
        assertEq(collection.balanceOf(address(456)), 1);
        assertEq(collection.totalMinted(), 3);
    }

    function test_ReduceSupply() public {
        vm.prank(creator);
        collection.reduceSupply(2);
        assertEq(collection.maxSupply(), 2);
    }

    function testRevert_ReduceSupply() public {
        vm.prank(creator);
        vm.expectRevert(IERC721Collection.InvalidSupplyConfig.selector);
        collection.reduceSupply(150);
    }

    function testRevert_ReduceSupply2() public {
        vm.deal(address(789), 250);
        _mintPublic(collection, address(789), 2, singleMintCost * 2);
        vm.prank(creator);
        vm.expectRevert(IERC721Collection.InvalidSupplyConfig.selector);
        collection.reduceSupply(1);
        assertEq(collection.maxSupply(), 100);
    }

    function testRevert_MintWhilePaused() public {
        address minter = address(567);
        vm.prank(creator);
        collection.pauseSale();
        deal(minter, 350);
        vm.expectRevert();
        _mintPublic(collection, address(567), 2, singleMintCost * 2);
    }

    function testMintAfterResume() public {
        address minter = address(567);
        vm.startPrank(creator);
        collection.pauseSale();
        collection.resumeSale();
        vm.stopPrank();
        deal(minter, 350);
        _mintPublic(collection, address(567), 2, singleMintCost * 2);
    }

    function _mintWhitelist(address _to, uint8 _amount, uint8 _phaseId, uint256 _value, uint256 _startTime) internal {
        vm.startPrank(_to);
        skip(_startTime);
        collection.whitelistMint{value: _value}(proof, _amount, _phaseId);
        vm.stopPrank();
    }

    function testWhitelistMint() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 1, 0, 70, collection.getPresaleConfig()[0].startTime);
    }

    function testWhitelistMintMultiple() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 2, 0, 120, collection.getPresaleConfig()[0].startTime);
    }

    function testRevertNonWhitelistedMinter() public {
        address minter = address(999);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        uint256 _startTime = collection.getPresaleConfig()[0].startTime;
        vm.expectRevert();
        _mintWhitelist(minter, 1, 0, 70, _startTime);
    }

    function testRevertWhitelistMintLimit() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        uint256 _startTime = collection.getPresaleConfig()[0].startTime;
        vm.expectRevert();
        _mintWhitelist(minter, 3, 0, 180, _startTime);
    }

    function testRevert_TradeWhileNotUnlocked() public {
        address minter = address(345);
        deal(minter, 350);
        _mintPublic(collection, minter, 1, singleMintCost);
        vm.expectRevert();
        collection.safeTransferFrom(minter, address(456), 1);
    }

    function testTradingAfterUnlocked() public {
        address minter1 = address(345);
        address minter2 = address(456);
        address marketPlace = address(789);
        deal(minter1, 350);
        deal(minter2, 350);
        vm.prank(creator);
        collection.unlockTrading();
        _mintPublic(collection, minter1, 2, singleMintCost * 2);
        _mintPublic(collection, minter2, 2, singleMintCost * 2);
        vm.prank(minter1);
        collection.approve(marketPlace, 1);
        vm.prank(minter2);
        collection.approve(marketPlace, 4);
        vm.startPrank(marketPlace);
        collection.safeTransferFrom(minter1, address(789), 1);
        collection.safeTransferFrom(minter2, address(789), 4);
        vm.stopPrank();
    }

    function testEditAndRemovePhase() public {
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        collection.addPresalePhase(presalePhaseConfig1);
        assertEq(collection.getPresaleConfig().length, 2);
        collection.editPresalePhaseConfig(1, presalePhaseConfig2);
        assertEq(collection.getPresaleConfig()[1].name, "Test Phase 2");
        vm.warp(0);
        collection.removePresalePhase(1);
        assertEq(collection.getPresaleConfig().length, 1);
        assertEq(collection.getPresaleConfig()[0].name, "Test Phase");
        vm.stopPrank();
    }

    function testUnrevealedURI() public {
        assertEq(collection.baseURI(), "https://example.com/");
        deal(address(345), 300);
        _mintPublic(collection, address(345), 1, singleMintCost);
        assertEq(collection.tokenURI(1), "https://example.com/");
        vm.prank(creator);
        collection.reveal("https://newURI.com/");
        assertEq(collection.tokenURI(1), "https://newURI.com/1");
    }

    function testRoyaltyInfo() public {
        assertEq(collection.royaltyFeeReceiver(), creator);
        deal(address(345), 300);
        _mintPublic(collection, address(345), 1, singleMintCost);
        (address receiver, uint256 royaltyValue) = collection.royaltyInfo(1, singleMintCost);
        assertEq(receiver, creator);
        assertEq(royaltyValue, 5);
    }

    function testOwner() public {
        assertEq(collection.owner(), creator);
        vm.prank(creator);
        collection.transferOwnership(address(456));
        assertEq(collection.owner(), address(456));
    }

    function testSupply() public view {
        assertEq(collection.maxSupply(), 100);
        assertEq(collection.totalMinted(), 0);
    }

    function testBurn() public {
        address minter = address(345);
        deal(minter, 300);
        _mintPublic(collection, minter, 1, singleMintCost);
        vm.prank(minter);
        collection.burn(1);
        assertEq(collection.balanceOf(minter), 0);
        assertEq(collection.totalMinted(), 0);
        assertEq(collection.maxSupply(), 100);
    }

    function testSetRoyaltyInfo() public {
        assertEq(collection.royaltyFeeReceiver(), creator);
        vm.prank(creator);
        collection.setRoyaltyInfo(address(456), 1000);
        assertEq(collection.royaltyFeeReceiver(), address(456));
    }
}
