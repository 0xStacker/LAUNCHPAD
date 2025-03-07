// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Collection} from "./IERC721Collection.sol";
import {Drop} from "./ERC721Collection.sol";

contract ERC721Factory {
    address internal feeReceiver;
    address admin;

    constructor(address _feeReceiver) {
        feeReceiver = _feeReceiver;
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    function createCollection(
        IERC721Collection.Collection memory _collection,
        IERC721Collection.PublicMint memory _publicMint,
        IERC721Collection.Platform memory _platform
    ) external returns (address) {
        Drop collection = new Drop(
            _collection,
            _publicMint,
            _platform
            );
        return address(collection);
    }

    function setFeeReceiver(address _feeReceiver) external onlyAdmin {
        require(msg.sender == admin, "Not admin");
        feeReceiver = _feeReceiver;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function getFeeReceiver() external view returns (address) {
        return feeReceiver;
    }
}
