// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";
import {IERC721Collection} from "./IERC721Collection.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {Phase} from "./PhaseLib.sol";

/**
* @dev Implementation of an ERC721 drop.

*/

contract Drop is ERC721{
    
    uint8 constant PHASELIMIT = 5;
    
    uint8 constant BATCH_MINT_LIMIT = 8;

    address public immutable owner;

    address private immutable _FEE_RECEIPIENT;

    bool public paused;
    
    uint64 public MAX_SUPPLY;
    
    uint64 public totalMinted;

    uint private immutable price;
    
    uint private tokenId;
    
    uint private royalty;

    

/*** @dev Platform mint fee */
    uint public mintFee;
    
    Phase.PublicMint internal _publicMint;

    // Sequential phase identities, 0 represents the public minting phase.
    uint8 internal phaseIds;
    Phase.PresalePhase[5] public mintPhases;

    mapping(uint8 => bool) public phaseCheck;
 
    Phase.PresalePhase[] internal _returnablePhases;
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
    address _feeReceipient) ERC721(_name, _symbol){
        MAX_SUPPLY = _maxSupply;
        price = _price;
        // Ensure that owner is an EOA and not zero address
        require(_owner.code.length == 0 && _owner != address(0), "Invalid Adress");
        owner = _owner;
        _FEE_RECEIPIENT = _feeReceipient;
        mintFee = _mintFee;
        _publicMint.startTime = block.timestamp + _startTime;
        _publicMint.endTime = block.timestamp + _startTime + _duration;
        _publicMint.price = _price;
        _publicMint.maxPerWallet = _maxPerWallet;
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
    * @dev Public minting function.
    * @param _amount is the amount of nfts to mint
    * @param _to is the address to mint the tokens to
    * @notice can only mint when public sale has started and the minting process is not paused by the creator
    * @notice minting is limited to the maximum amounts allowed on the public mint phase.
    */

    function mintPublic(uint _amount, address _to) external payable phaseActive(0) limit(_to, _amount, 0) isPaused{
        if (!_canMint(_amount)){
            revert SoldOut(MAX_SUPPLY);
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
    * @dev adds new presale phase for contract
    * @param _phase is the new phase to be added
    * @notice phases are identified sequentially using numbers, starting from 1.
    */
    function addPresalePhase(Phase.PresalePhaseIn calldata _phase) external onlyCreator{
        if (phaseIds == PHASELIMIT){
            revert PhaseLimitExceeded(PHASELIMIT);  
        }
        uint8 phaseId = phaseIds + 1;

        Phase.PresalePhase memory phase = Phase.PresalePhase({
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
    * @dev Remove presale phase
    * @param _phaseId is the identifier for the phase being removed
    */

    function removePhase(uint8 _phaseId) external onlyCreator{
        if (!phaseCheck[_phaseId]){
            revert InvalidPhase(_phaseId);
        }

        Phase.PresalePhase[] memory returnablePhases = _returnablePhases;
        delete _returnablePhases;
        for (uint8 i; i < returnablePhases.length; i++){
            if (returnablePhases[i].phaseId != _phaseId){
                _returnablePhases.push(returnablePhases[i]);
            }
        }

        delete mintPhases[_phaseId];
        phaseCheck[_phaseId] = false;
        emit RemovePresalePhase(mintPhases[_phaseId].name, _phaseId);
    }

    function reduceSupply(uint64 _newSupply) external onlyCreator{
        if(_newSupply >= totalMinted || _newSupply < totalMinted){
            revert InvalidSupplyConfig();
        }
        MAX_SUPPLY = _newSupply;
    }

    // getter for presale phase data
    function getPresaleData() external view returns(Phase.PresalePhase[] memory){
        return _returnablePhases;
    }

    // getter for public mint data
    function getPublicMintData() external view returns(Phase.PublicMint memory){
        return _publicMint;
    }

    /**
    * @dev Allows creator to airdrop NFTs to an account
    * @param _to is the address of the receipeient
    * @param _amount is the amount of NFTs to be airdropped
    * Ensures amount of tokens to be minted does not exceed MAX_SUPPLY*/

    function airdrop(address _to, uint _amount) external onlyCreator{
        if(!_canMint(_amount)){
            revert SoldOut(MAX_SUPPLY);
        }
        _mintNft(_to, _amount);
        emit Airdrop(_to, tokenId, _amount);
    }
    
    /**
    * @dev Allows the creator to airdrop NFT to multiple addresses at once.
    * @param _receipients is the list of accounts to mint NFT for.
    * @param _amountPerAddress is the amount of tokens to be minted per addresses.
    * Ensures total amount of NFT to be minted does not exceed MAX_SUPPLY.
    * */
    function batchAirdrop(address[] calldata _receipients, uint _amountPerAddress) external onlyCreator{
        if(_receipients.length > BATCH_MINT_LIMIT){
            revert AmountTooHigh();
        }

        uint totalAmount = _amountPerAddress * _receipients.length;
        if (!_canMint(totalAmount)){
            revert SoldOut(MAX_SUPPLY);
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
    function withdraw(uint _amount) external onlyCreator{
        if (address(this).balance < _amount){
            revert InsufficientFunds(_amount);
        }
        (bool success, ) = payable(owner).call{value: _amount}("");
        if (!success){
            revert WithdrawalFailed();
        }
        emit WithdrawFunds(_amount);
    }

    /**
    * @dev Check the whitelist status of an account based on merkle proof.
    * @param _proof is a merkle proof to check for verification.
    * @param _amount is the amount of tokens to be minted.
    * @param _phaseId is the presale phase the user is attempting to mint for.
    * @notice If phase is not active, function reverts.
    * @notice If amount exceeds the maximum allowed to be minted per walllet, function reverts.
    */

    function whitelistMint(bytes32[] memory _proof, uint8 _amount, uint8 _phaseId) external payable phaseActive(_phaseId) limit(msg.sender, _amount, _phaseId) isPaused{
        if (!phaseCheck[_phaseId]){
            revert InvalidPhase(_phaseId);
        }
        // PresalePhase memory phase = phases[_phaseId];
        if (!_canMint(_amount)){
            revert SoldOut(MAX_SUPPLY);
        }
        
        // get mint cost
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
    * @dev Allows owner to burn their nft
    */
    function burn(uint _tokenId) external tokenOwner(_tokenId){
        _burn(_tokenId);
    }

      // total supply
    function supply() external view returns(uint){
        return MAX_SUPPLY;
    }

    function contractOwner() external view rerturns(address){
        return owner;
    }
 
    /**
    * @dev Checks if a certain amount of token can be minted. 
    * @param _amount is the amount of tokens to be minted.
    * @notice Ensures that minting _amount tokens does not cause the total minted tokens to exceed max supply.
    */
    function _canMint(uint _amount) internal view returns (bool){
        if (totalMinted + _amount > MAX_SUPPLY){
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
     */

    function _payoutPlatformFee(uint _amount) internal{
        uint fee = mintFee * _amount;
        (bool success, ) = payable(_FEE_RECEIPIENT).call{value: fee}("");
        if(!success){
            revert PurchaseFailed();
        }
    }

    function _payCreator(uint _amount) internal{
        uint fee = mintFee * _amount;
        (bool success, ) = payable(owner).call{value: msg.value - fee}("");
        if(!success){
            revert PurchaseFailed();
        }
    }
    
    /**
     * @dev Safe minting function that will mint n amount of tokens to an address.
     * @param _to is the address of the receipient.
     * @param _amount is the amount of tokens to be minted.
    */

    function _mintNft(address _to, uint _amount) internal isPaused {  
        for(uint i; i < _amount; i++){
            tokenId += 1;
            totalMinted += 1;
            _safeMint(_to, tokenId);
        }
    }
}