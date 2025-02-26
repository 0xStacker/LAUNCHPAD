// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test, console} from "forge-std/Test.sol";
import {Drop} from "../src/ERC721Collection.sol";
import {IERC721Collection} from "../src/IERC721Collection.sol";

/***
 * string memory _name,
    string memory _symbol,
    uint64 _maxSupply,
    uint _startTime,
    uint _duration,
    uint _mintFee,
    uint _price,
    uint8 _maxPerWallet,
    address _owner,
    string memory _baseUri,
    address _feeReceipient
 */

contract ERC721CollectionTest is Test{
    Drop public collection;

    function setUp() public {
        deal(address(123), 200);
        collection = new Drop(
            "Test Collection",
            "TST",
            100,
            0,
            100,
            10,
            100,
            2,
            address(123),
            "https://example.com/",
            address(234)
        );
    }

    function test_Mint() public {
        hoax(address(456), 300);
        assertEq(address(456).balance, 300);
        collection.mintPublic{value: 110}(1, address(456));
        assertEq(collection.balanceOf(address(456)), 1);
        collection.mintPublic{value: 110}(1, address(456));
        assertEq(collection.balanceOf(address(456)), 2);
    }

    function test_AddPresale() public{
        uint startTimeInSec = 0;
        uint endTimeInSec = 100;
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
}