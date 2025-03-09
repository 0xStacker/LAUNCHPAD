// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Collection} from "./IERC721Collection.sol";
import {Drop} from "./ERC721Collection.sol";

contract ERC721CollectionFactory {
    uint64 public platformSalesFeeBps;
    address public feeReceiver;
    address public admin;
    uint256 public platformMintFee;
    mapping(address _creator => address[] _collection) public collections;

    constructor(address _initialFeeReceiver, uint256 _initialPlatformMintFee, uint64 _initialPlatformSalesFeeBps) {
        feeReceiver = _initialFeeReceiver;
        platformMintFee = _initialPlatformMintFee;
        platformSalesFeeBps = _initialPlatformSalesFeeBps;
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    function createCollection(
        IERC721Collection.Collection memory _collection,
        IERC721Collection.PublicMint memory _publicMint
    ) external returns (address) {
        IERC721Collection.Platform memory platform = IERC721Collection.Platform({
            feeReceipient: feeReceiver,
            mintFee: platformMintFee,
            salesFeeBps: platformSalesFeeBps
        });
        Drop collection = new Drop(_collection, _publicMint, platform);
        collections[msg.sender].push(address(collection));
        return address(collection);
    }

    function setFeeReceiver(address _feeReceiver) external onlyAdmin {
        require(msg.sender == admin, "Not admin");
        feeReceiver = _feeReceiver;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function setPlatformSalesFeBps(uint8 _newBps) external onlyAdmin {
        platformSalesFeeBps = _newBps;
    }

    function setPlatformMintFee(uint256 _newFee) external onlyAdmin {
        platformMintFee = _newFee;
    }

    function getCreatorCollections(address _creator) external view returns (address[] memory) {
        return collections[_creator];
    }
}
