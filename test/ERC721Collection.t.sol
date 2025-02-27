// SPDX-License-Identifier: UNLICENSED
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

    function setUp() public {
        deal(address(123), 200);
        collection =
            new Drop("Test Collection", "TST", 100, 0, 100, 10, 100, 2, creator, "https://example.com/", platform);
    }

    function _mintPublic(address _to, uint256 _amount, uint256 _value) internal {
        uint256 previousBalance = collection.balanceOf(address(_to));
        uint256 previousTotalMinted = collection.totalMinted();
        uint256 previousCreatorBalance = creator.balance;
        console.log("Creator previous balance: ", previousCreatorBalance);
        uint256 previousPlatformBalance = platform.balance;
        console.log("Platform previous balance: ", previousPlatformBalance);
        vm.prank(_to);
        if (_amount > publicMintLimit) {
            vm.expectRevert(IERC721Collection.PhaseLimitExceeded.selector);
            collection.mintPublic{value: _value}(_amount, address(_to));
        } else {
            collection.mintPublic{value: _value}(_amount, address(_to));
            uint256 creatorNewBalance =
                previousCreatorBalance + collection.computeShare(_amount, IERC721Collection.Payees.CREATOR);
            uint256 platformNewBalance =
                previousPlatformBalance + collection.computeShare(_amount, IERC721Collection.Payees.PLATFORM);
            console.log("Creator new balance: ", creatorNewBalance);
            console.log("Platform new balance: ", platformNewBalance);
            assertEq(collection.balanceOf(address(_to)), previousBalance + _amount);
            assertEq(collection.totalMinted(), previousTotalMinted + _amount);
            assertEq(creator.balance, creatorNewBalance);
            assertEq(platform.balance, platformNewBalance);
        }
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
        IERC721Collection.PresalePhaseIn memory phase = IERC721Collection.PresalePhaseIn({
            maxPerAddress: 2,
            name: "Test Phase",
            price: 100,
            startTime: startTimeInSec,
            endTime: endTimeInSec,
            merkleRoot: bytes32(0)
        });
        vm.prank(address(123));
        collection.addPresalePhase(phase);
        assertEq(collection.getPresaleData().length, 1);
        assertEq(collection.getPresaleData()[0].maxPerAddress, 2);
        assertEq(collection.getPresaleData()[0].name, "Test Phase");
        assertEq(collection.getPresaleData()[0].price, 100);
        assertEq(collection.getPresaleData()[0].startTime, block.timestamp + startTimeInSec);
        assertEq(collection.getPresaleData()[0].endTime, block.timestamp + endTimeInSec);
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
        vm.startPrank(address(123));
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        collection.addPresalePhase(phase);
        vm.stopPrank();
    }

    function testAirdrop() public {
        vm.prank(address(123));
        collection.airdrop(address(234), 3);
        assertEq(collection.balanceOf(address(234)), 3);
        assertEq(collection.totalMinted(), 3);
    }

    function test_batchAirdrop() public {
        address[] memory addresses = new address[](3);
        addresses[0] = address(234);
        addresses[1] = address(345);
        addresses[2] = address(456);
        vm.prank(address(123));
        collection.batchAirdrop(addresses, 2);
        assertEq(collection.balanceOf(address(234)), 2);
        assertEq(collection.balanceOf(address(345)), 2);
        assertEq(collection.balanceOf(address(456)), 2);
        assertEq(collection.totalMinted(), 6);
    }

    function test_ReduceSupply() public {
        vm.prank(address(123));
        collection.reduceSupply(50);
        assertEq(collection.maxSupply(), 50);
    }

    function testFail_ReduceSupply() public {
        vm.prank(address(123));
        collection.reduceSupply(150);
    }

    function testFail_ReduceSupply2() public {
        vm.deal(address(789), 250);
        vm.prank(address(789));
        _mintPublic(address(789), 2, singleMintCost * 2);
        vm.prank(address(123));
        collection.reduceSupply(1);
        assertEq(collection.maxSupply(), 100);
    }
}
