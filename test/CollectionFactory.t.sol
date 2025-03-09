// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC721CollectionFactory} from "../src/ERC721CollectionFactory.sol";
import {IERC721Collection} from "../src/IERC721Collection.sol";

contract FactoryTest is Test {
    address admin = address(123);
    ERC721CollectionFactory factory;

    function setUp() public {
        vm.prank(admin);
        ERC721CollectionFactory _factory = new ERC721CollectionFactory(admin, 100, 10_00);
        factory = _factory;
    }

    function testCreateCollection() public {
        vm.startPrank(address(234));
        IERC721Collection.Collection memory collection = IERC721Collection.Collection({
            tradingLocked: false,
            revealed: false,
            maxSupply: 100,
            owner: address(this),
            proceedCollector: address(0),
            royaltyReceipient: address(0),
            name: "Test Collection",
            symbol: "TST",
            baseURI: "https://test.com/",
            royaltyFeeBps: 10
        });

        IERC721Collection.PublicMint memory publicMint = IERC721Collection.PublicMint({
            maxPerWallet: 10,
            startTime: block.timestamp,
            endTime: block.timestamp + 1000,
            price: 100
        });

        factory.createCollection(collection, publicMint);
        factory.createCollection(collection, publicMint);
        vm.stopPrank();
        assertEq(factory.getCreatorCollections(address(234)).length, 2);
    }

    function testSetFeeReceiver() public {
        vm.prank(admin);
        factory.setFeeReceiver(address(234));
        assertEq(factory.feeReceiver(), address(234));
    }

    function testSetAdmin() public {
        vm.prank(admin);
        factory.setAdmin(address(234));
        assertEq(factory.admin(), address(234));
    }

    function testSetPlatformSalesFeBps() public {
        vm.prank(admin);
        factory.setPlatformSalesFeBps(20);
        assertEq(factory.platformSalesFeeBps(), 20);
    }
}
