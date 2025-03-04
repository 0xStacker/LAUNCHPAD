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
        string memory _name,
        string memory _symbol,
        uint64 _maxSupply,
        uint256 _mintFee,
        IERC721Collection.PublicMint memory _publicMint,
        string memory _baseURI,
        bool _lockedTillMintOut
    ) external returns (address) {
        Drop collection = new Drop(
            _name, _symbol, _maxSupply, _publicMint, _mintFee, msg.sender, _baseURI, feeReceiver, _lockedTillMintOut
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
