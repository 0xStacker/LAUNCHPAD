// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";
import {IERC721Collection} from "./IERC721Collection.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";

/**
* @dev Implementation of an ERC721 drop.
*/

contract Drop is ERC721, IERC721Collection, ReentrancyGuard{
    
    uint8 constant PHASELIMIT = 5;
    
    uint8 constant BATCH_MINT_LIMIT = 8;

    address public immutable owner;

    address private immutable _FEE_RECEIPIENT;

    bool public paused;
    
    uint64 public maxSupply;
   
    uint64 private tokenId;
    
    uint64 public totalMinted;

    uint private immutable price;
    
    // uint private constant royalty;

    string baseURI;

    

/*** @dev Platform mint fee */
    uint public immutable mintFee;
    
    PublicMint internal _publicMint;

    // Sequential phase identities, 0 represents the public minting phase.
    uint8 internal phaseIds;
    /**
     * @dev All presale phase data.
     * Maximum of 5 presale phases.
     */
    PresalePhase[5] public mintPhases;

    mapping(uint8 => bool) public phaseCheck;
 
    PresalePhase[] internal _returnablePhases;
    using MerkleProof for bytes32[];


    /**
    * @dev Initialize contract by setting necessary data.
    * @param _name is the name of the collection.
    * @param _symbol is the collection symbol.
    * @param _maxSupply is the maximum supply of the collection.
    * @param _startTime is the start time for the public mint.
    * @param _duration is the mint duration for the public mint.
    * @param _owner is the address of the collection owner
    * @param _mintFee is the platform mint fee.
    * @param _price is the mint price per nft for public mint.
    * @param _maxPerWallet is the maximum nfts allowed to be minted by a wallet during the public mint
    * @param _baseUri is the base uri for the collection.
    * @param _feeReceipient is the platform fee receipient. 
    */

    constructor(string memory _name,
    string memory _symbol,
    uint64 _maxSupply,
    uint _startTime,
    uint _duration,
    uint _mintFee,
    uint _price,
    uint8 _maxPerWallet,
    address _owner,
    string memory _baseUri,
    address _feeReceipient) ERC721(_name, _symbol) ReentrancyGuard(){
        maxSupply = _maxSupply;
        price = _price;
        // Ensure that owner is an EOA and not zero address
        require(_owner.code.length == 0 && _owner != address(0), "Invalid Adress");
        owner = _owner;
        if (_feeReceipient == address(0)){
            revert ERC721InvalidReceiver(address(0));
        }
        _FEE_RECEIPIENT = _feeReceipient;
        mintFee = _mintFee;
        _publicMint.startTime = block.timestamp + _startTime;
        _publicMint.endTime = block.timestamp + _startTime + _duration;
        _publicMint.price = _price;
        _publicMint.maxPerWallet = _maxPerWallet;
        baseURI = _baseUri;
    }

    receive() external payable { }

    fallback() external payable { }

    // Enforce Creator priviledges
    modifier onlyCreator{
        if (msg.sender != owner){
            revert NotCreator();}
        _;
    }

    // Enforce token owner priviledges
    modifier tokenOwner(uint _tokenId){
        address _owner = _requireOwned(_tokenId);
        if(_owner != msg.sender){
            revert NotOwner();
        }
        _;
    }

    // Block minting unless phase is active
    modifier phaseActive(uint8 _phaseId){
        if (_phaseId == 0){
            require(_publicMint.startTime <= block.timestamp && block.timestamp <= _publicMint.endTime, "Phase Inactive");
        }

        else{
            uint phaseStartTime = mintPhases[_phaseId].startTime;
            uint phaseEndTime = mintPhases[_phaseId].endTime;
            require(phaseStartTime <= block.timestamp && block.timestamp <= phaseEndTime, "Phase Inactive");
        }
        _;
    }

    // Allows owner to pause minting at any phase.
    modifier isPaused{
        if(paused){
            revert SaleIsPaused();
        }
        _;
    }

    /**
    * @dev Enforce phase minting limit per address.  
    */

    modifier limit(address _to, uint _amount, uint8 _phaseId){
        if(_phaseId == 0){
            require(balanceOf(_to) + _amount <= _publicMint.maxPerWallet, "Mint Limit Exceeded");
        }
        else{
            uint8 phaseLimit = mintPhases[_phaseId].maxPerAddress;
            require(balanceOf(_to) + _amount <= phaseLimit, "Mint Limit Exceeded");
        }
        _;
    }

    /**
     * @dev see {IERC721Collection-mintPublic}
     */
    function mintPublic(uint _amount, address _to) external payable phaseActive(0) limit(_to, _amount, 0) isPaused nonReentrant{
        if (!_canMint(_amount)){
            revert SoldOut(maxSupply);
        }
        uint totalCost = _getCost(0, _amount);
        if(msg.value < totalCost){
            revert InsufficientFunds(totalCost);
        }
        _mintNft(_to, _amount);
        _payoutPlatformFee(_amount);
        _payCreator(_amount);
        emit Purchase(_to, tokenId, _amount);
    }

    
    /**
     * @dev see {IERC721Collection-addPresalePhase}
     */
    function addPresalePhase(PresalePhaseIn calldata _phase) external onlyCreator{
        if (phaseIds == PHASELIMIT){
            revert PhaseLimitExceeded(PHASELIMIT);  
        }
        uint8 phaseId = phaseIds + 1;

        PresalePhase memory phase = PresalePhase({
            name: _phase.name,
            startTime: block.timestamp + _phase.startTime,
            endTime: block.timestamp + _phase.endTime,
            maxPerAddress: _phase.maxPerAddress,
            price: _phase.price,
            merkleRoot: _phase.merkleRoot,
            phaseId: phaseId});

            mintPhases[phaseId] = phase;
            mintPhases[phaseId].startTime = mintPhases[phaseId].startTime + block.timestamp;
            mintPhases[phaseId].endTime = mintPhases[phaseId].endTime + block.timestamp;
            phaseCheck[phaseId] = true;
            _returnablePhases.push(phase);
            phaseIds += 1;
            if(_returnablePhases.length > PHASELIMIT){
                revert MaxPhaseLimit();
            }
            emit AddPresalePhase(_phase.name, phaseId);
    }

    /**
     * @dev see {IERC721Collection-reduceSupply}
     */
    function reduceSupply(uint64 _newSupply) external onlyCreator{
        if(_newSupply > totalMinted || _newSupply > maxSupply){
            revert InvalidSupplyConfig();
        }
        maxSupply = _newSupply;
        emit SupplyReduced(_newSupply);
    }

    // getter for presale phase data
    function getPresaleData() external view returns(PresalePhase[] memory){
        return _returnablePhases;
    }

    // getter for public mint data
    function getPublicMintData() external view returns(PublicMint memory){
        return _publicMint;
    }
    
    /***
     * @dev see {IERC721Collection-airdrop}
     */
    function airdrop(address _to, uint _amount) external onlyCreator{
        if(!_canMint(_amount)){
            revert SoldOut(maxSupply);
        }
        _mintNft(_to, _amount);
        emit Airdrop(_to, tokenId, _amount);
    }

    /***
     * @dev see {IERC721Collection-batchAirdrop}
     */
    function batchAirdrop(address[] calldata _receipients, uint _amountPerAddress) external onlyCreator{
        if(_receipients.length > BATCH_MINT_LIMIT){
            revert AmountTooHigh();
        }

        uint totalAmount = _amountPerAddress * _receipients.length;
        if (!_canMint(totalAmount)){
            revert SoldOut(maxSupply);
        }
        for(uint i; i < _receipients.length; i++){
            _mintNft(_receipients[i], _amountPerAddress);
        }
        emit BatchAirdrop(_receipients, _amountPerAddress);
    }
    
    // Pause mint process
    function pauseSale() external onlyCreator{
        paused = true;
        emit SalePaused();
    }

    // Resume mint process
    function resumeSale() external onlyCreator{
        paused = false;
        emit ResumeSale();
    }

    // Withdraw funds from contract
    function withdraw(uint _amount) external onlyCreator nonReentrant{
        if (address(this).balance < _amount){
            revert InsufficientFunds(_amount);
        }
        (bool success, ) = payable(owner).call{value: _amount}("");
        if (!success){
            revert WithdrawalFailed();
        }
        emit WithdrawFunds(_amount);
    }

    /***
     * @dev see {IERC721Collection-whitelistMint}
     */
    function whitelistMint(bytes32[] memory _proof, uint8 _amount, uint8 _phaseId) external payable phaseActive(_phaseId) limit(msg.sender, _amount, _phaseId) nonReentrant isPaused{
        if (!phaseCheck[_phaseId]){
            revert InvalidPhase(_phaseId);
        }
        if (!_canMint(_amount)){
            revert SoldOut(maxSupply);
        }
        uint totalCost = _getCost(_phaseId, _amount);
        if (msg.value < totalCost){
            revert InsufficientFunds(totalCost);
        }

        bool whitelisted = _proof.verify(mintPhases[_phaseId].merkleRoot, keccak256(abi.encodePacked(msg.sender))); 
        if(!whitelisted){
            revert NotWhitelisted(msg.sender);
        }
        _mintNft(msg.sender, _amount);
        _payoutPlatformFee(_amount);
        _payCreator(_amount);
    }

    /**
    * @dev see {ERC721-_burn}
    */
    function burn(uint _tokenId) external tokenOwner(_tokenId){
        _burn(_tokenId);
    }

      // total supply
    function supply() external view returns(uint){
        return maxSupply;
    }

    function setBaseURI(string memory _uri) external onlyCreator{
        baseURI = _uri;
    }   

    /***
     * @dev see {IERC721Collection-contractOwner}
     */
    function contractOwner() external view returns(address){
        return owner;
    }
    /***
     * @dev see {ERC721-_baseURI}
     */
    function _baseURI() internal view override returns(string memory){
        return baseURI;
    }

    /**
    * @dev Checks if a certain amount of token can be minted. 
    * @param _amount is the amount of tokens to be minted.
    * @notice Ensures that minting _amount tokens does not cause the total minted tokens to exceed max supply.
    */
    function _canMint(uint _amount) internal view returns (bool){
        if (totalMinted + _amount > maxSupply){
            return false;
        } else{
            return true;
        }
    }


    /**
    * @dev Compute the cost of minting a certain amount of tokens.
    * @param _amount is the amount of tokens to be minted.
    */
    function _getCost(uint8 _phaseId, uint _amount) public view returns (uint cost){
        if (_phaseId == 0){
            return (price * _amount) + (mintFee * _amount);
        }

        else{
            return (mintPhases[_phaseId].price * _amount) + (mintFee * _amount);
        }

    }

    /***
     * @dev Payout platform fee
     * @param _amount is the amount of ether to be paid to the platform as fee.
     */

    function _payoutPlatformFee(uint _amount) internal{
        uint fee = mintFee * _amount;
        (bool success, ) = payable(_FEE_RECEIPIENT).call{value: fee}("");
        if(!success){
            revert PurchaseFailed();
        }
    }

    /**
     * @dev pay creator
     * @param _amount is the amount of ether to be paid to creator after paying platform fee.
     */
    function _payCreator(uint _amount) internal{
        uint fee = mintFee * _amount;
        (bool success, ) = payable(owner).call{value: msg.value - fee}("");
        if(!success){
            revert PurchaseFailed();
        }
    }
    
    /**
     * @dev Mint tokens to an address.
     * @param _to is the address of the receipient.
     * @param _amount is the amount of tokens to be minted.
    */

    function _mintNft(address _to, uint _amount) internal isPaused {  
        uint64 tokenIdInc;
        uint64 totalMintedInc;
        for(uint i; i < _amount; i++){
            tokenIdInc += 1;
            totalMintedInc += 1;
            _safeMint(_to, tokenId);
        }
        tokenId += tokenIdInc;
        totalMinted += totalMintedInc; 
    }
}