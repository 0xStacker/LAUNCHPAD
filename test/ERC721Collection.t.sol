// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Drop} from "../src/ERC721Collection.sol";
import {IERC721Collection} from "../src/IERC721Collection.sol";

contract ERC721CollectionTest is Test {
    Drop public collection;
    uint256 public singleMintCost = 110;
    uint256 publicMintLimit = 2;
    address platform = address(234);
    address creator = address(123);
    bool lockedTillMintOut = true;
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

    function setUp() public {
        deal(creator, 200);
        collection = new Drop(
            "Test Collection",
            "TST",
            4,
            publicMintConfig,
            10,
            creator,
            "https://example.com/",
            platform,
            lockedTillMintOut
        );
    }

    function _mintPublic(address _to, uint256 _amount, uint256 _value) internal {
        uint256 previousBalance = collection.balanceOf(address(_to));
        uint256 previousTotalMinted = collection.totalMinted();
        uint256 previousCreatorBalance = creator.balance;
        console.log("Creator previous balance: ", previousCreatorBalance);
        uint256 previousPlatformBalance = platform.balance;
        console.log("Platform previous balance: ", previousPlatformBalance);
        vm.prank(_to);

        collection.mintPublic{value: _value}(_amount, address(_to));
        uint256 creatorNewBalance =
            previousCreatorBalance + collection.computeShare(_amount, 0, IERC721Collection.Payees.CREATOR);
        uint256 platformNewBalance =
            previousPlatformBalance + collection.computeShare(_amount, 0, IERC721Collection.Payees.PLATFORM);
        console.log("Creator new balance: ", creatorNewBalance);
        console.log("Platform new balance: ", platformNewBalance);
        assertEq(collection.balanceOf(address(_to)), previousBalance + _amount);
        assertEq(collection.totalMinted(), previousTotalMinted + _amount);
        assertEq(creator.balance, creatorNewBalance);
        assertEq(platform.balance, platformNewBalance);
    }

    function test_publicMint() public {
        address minter = address(456);
        deal(minter, 350);
        _mintPublic(minter, 1, singleMintCost);
    }

    function testFail_publicMintLimit() public {
        address minter = address(456);
        deal(minter, 350);
        _mintPublic(minter, 3, singleMintCost * 3);
    }

    function test_mintMultiple() public {
        address minter = address(456);
        deal(minter, 350);
        _mintPublic(minter, 2, singleMintCost * 2);
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

    function testFail_presaleLimit() public {
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

    function testFail_ReduceSupply() public {
        vm.prank(creator);
        collection.reduceSupply(150);
    }

    function testFail_ReduceSupply2() public {
        vm.deal(address(789), 250);
        vm.prank(address(789));
        _mintPublic(address(789), 2, singleMintCost * 2);
        vm.prank(creator);
        collection.reduceSupply(1);
        assertEq(collection.maxSupply(), 100);
    }

    function testFail_MintWhilePaused() public {
        address minter = address(567);
        vm.prank(creator);
        collection.pauseSale();
        deal(minter, 350);
        _mintPublic(address(567), 2, singleMintCost * 2);
    }

    function testMintAfterResume() public {
        address minter = address(567);
        vm.startPrank(creator);
        collection.pauseSale();
        collection.resumeSale();
        vm.stopPrank();
        deal(minter, 350);
        _mintPublic(address(567), 2, singleMintCost * 2);
    }

    function _mintWhitelist(address _to, uint8 _amount, uint8 _phaseId, uint256 _value) internal {
        uint256 previousBalance = collection.balanceOf(address(_to));
        uint256 previousTotalMinted = collection.totalMinted();
        uint256 previousCreatorBalance = creator.balance;
        console.log("Creator previous balance: ", previousCreatorBalance);
        uint256 previousPlatformBalance = platform.balance;
        console.log("Platform previous balance: ", previousPlatformBalance);
        vm.startPrank(_to);
        skip(collection.getPresaleConfig()[0].startTime);
        collection.whitelistMint{value: _value}(proof, _amount, _phaseId);
        vm.stopPrank();
        uint256 creatorNewBalance =
            previousCreatorBalance + collection.computeShare(_amount, _phaseId, IERC721Collection.Payees.CREATOR);
        uint256 platformNewBalance =
            previousPlatformBalance + collection.computeShare(_amount, _phaseId, IERC721Collection.Payees.PLATFORM);
        console.log("Creator new balance: ", creatorNewBalance);
        console.log("Platform new balance: ", platformNewBalance);
        assertEq(collection.balanceOf(address(_to)), previousBalance + _amount);
        assertEq(collection.totalMinted(), previousTotalMinted + _amount);
        assertEq(creator.balance, creatorNewBalance);
        assertEq(platform.balance, platformNewBalance);
    }

    function testWhitelistMint() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 1, 0, 70);
    }

    function testWhitelistMintMultiple() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 2, 0, 120);
    }

    function testFailNonWhitelistedMinter() public {
        address minter = address(999);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 1, 0, 70);
    }

    function testFailWhitelistMintLimit() public {
        address minter = address(345);
        vm.startPrank(creator);
        collection.addPresalePhase(presalePhaseConfig1);
        vm.stopPrank();
        deal(minter, 350);
        _mintWhitelist(minter, 3, 0, 180);
    }

    function testFail_TradeWhileNotSoldOut() public {
        address minter = address(345);
        deal(minter, 350);
        _mintPublic(minter, 1, singleMintCost);
        collection.safeTransferFrom(minter, address(456), 1);
    }

    function testTradingAfterSoldOut() public {
        address minter1 = address(345);
        address minter2 = address(456);
        address marketPlace = address(789);
        deal(minter1, 350);
        deal(minter2, 350);
        _mintPublic(minter1, 2, singleMintCost * 2);
        _mintPublic(minter2, 2, singleMintCost * 2);
        vm.prank(minter1);
        collection.approve(marketPlace, 1);
        vm.prank(minter2);
        collection.approve(marketPlace, 4);
        vm.startPrank(marketPlace);
        collection.safeTransferFrom(minter1, address(789), 1);
        collection.safeTransferFrom(minter2, address(789), 4);
        vm.stopPrank();
    }
}
