// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./IERC721Collection.sol";
import {Drop} from "./ERC721Collection.sol";

contract ERC721Factory{
    address private feeReceiver;
    address admin;

    constructor(address _feeReceiver){
        feeReceiver = _feeReceiver;
        admin = msg.sender;
    }

    modifier onlyAdmin(){
        require(msg.sender == admin, "Not admin");
        _;
    }
    
    function _createCollection(
        string memory _name,
        string memory _symbol,
        uint64 _maxSupply,
        uint _startTime,
        uint _duration,
        uint _mintFee,
        uint _price,
        uint8 _maxPerWallet,
        string memory _baseURI
    ) internal returns(address){
        Drop collection = new Drop(
            _name,
            _symbol,
            _maxSupply,
            _startTime,
            _duration,  
            _mintFee,
            _price,
            _maxPerWallet,
            msg.sender,
            _baseURI,
            feeReceiver);
        return address(collection);
    }

    function setFeeReceiver(address _feeReceiver) external onlyAdmin{
        require(msg.sender == admin, "Not admin");
        feeReceiver = _feeReceiver;
    }

}