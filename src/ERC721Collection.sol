// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Collection} from "./IERC721Collection.sol";
import {IERC2981} from "@openzeppelin/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/utils/introspection/ERC165.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {BasisPointsCalculator} from "./BpsLib.sol";
import {ERC721URIStorage} from "@openzeppelin/token/ERC721/extensions/ERC721URIStorage.sol";

/**
 * @title Implementation of an ERC721 drop.
 * @author 0xstacker "github.com/0xStacker"
 */
contract Drop is ERC721, IERC721Collection, Ownable, ReentrancyGuard, IERC2981 {
    /// @dev Maximum number of presale phases that can be added.
    uint8 constant MAX_PRESALE_LIMIT = 5;

    /// @dev Maximum number of tokens that can be minted in a single transaction.
    uint8 constant BATCH_MINT_LIMIT = 8;

    // Sequential phase identities
    uint8 internal phaseIds;

    /// @dev If set to true, pauses minting of tokens.
    bool public paused;

    /// @dev If set to true, prevents trading of tokens until minting is complete.
    bool public tradingLocked;

    /**
     * @dev Set to false to conceal token URIs.
     * @notice If set to false, token URIs will not be revealed until creator reveals.
     * @notice All token URIs will default to the baseURI, so the base URI would hold the concealed data.
     * @notice A new baseURI will be set during reveal.
     */
    bool public revealed = true;

    /// @notice Maximum supply of collection
    uint64 public maxSupply;

    /// @notice Current token id
    uint64 private _tokenId;

    /// @notice Total number of minted tokens
    uint64 private _totalMinted;

    /// @dev Platform fee receipient
    address private immutable _FEE_RECEIPIENT;

    /// @notice Sale proceed collector. Defaults to owner address if not set on deployment.
    address proceedCollector;

    /// @notice Royalty fee receipient. defaults to owner address if not set on deployment.
    address public royaltyFeeReceiver;

    /// @dev Percentage paid to the platform by creator
    uint256 internal immutable SALES_FEE_BPS;

    /// @dev Royalty fee bps
    uint256 internal royaltyFeeBps;

    /// @dev Maximum allowed royalty fee
    uint256 constant MAX_ROYALTY_FEE = 10_00;

    string public baseURI;

    /**
     * @dev Fee paid to the platform per nft mint by user
     */
    uint256 public immutable mintFee;

    /// @dev public mint configuration
    PublicMint private _publicMint;

    /**
     * @dev presale mint phases.
     * Maximum of 5 presale phases.
     */
    PresalePhase[] public mintPhases;

    mapping(uint8 => bool) public phaseCheck;

    using MerkleProof for bytes32[];
    using BasisPointsCalculator for uint256;

    /**
     * @dev Initialize contract by setting necessary data.
     * @param _collection holds all collection related data. see {IERC721Collection-Collection}
     * @param _platform Holds all platform related data. see {IERC721Collection-Platform}
     * @param _publicMintConfig Is the public mint configuration for collection. see{IERC721Collection-PublicMint}
     */
    constructor(Collection memory _collection, PublicMint memory _publicMintConfig, Platform memory _platform)
        ERC721(_collection.name, _collection.symbol)
        ReentrancyGuard()
        Ownable(_collection.owner)
    {
        maxSupply = _collection.maxSupply;
        if (_platform.feeReceipient == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        _FEE_RECEIPIENT = _platform.feeReceipient;
        mintFee = _platform.mintFee;
        _publicMint = _publicMintConfig;
        if (_collection.royaltyReceipient == address(0)) {
            royaltyFeeReceiver = _collection.owner;
        }
        if (_collection.proceedCollector == address(0)) {
            proceedCollector = _collection.owner;
        }
        if (!_collection.revealed) {
            revealed = false;
        }
        baseURI = _collection.baseURI;
        royaltyFeeBps = _collection.royaltyFeeBps;
        SALES_FEE_BPS = _platform.salesFeeBps;
        tradingLocked = _collection.tradingLocked;
    }

    receive() external payable {}

    fallback() external payable {}

    ///////////////////////// MODIFIERS ////////////////////////////////////

    // Enforce token owner priviledges
    modifier tokenOwner(uint256 tokenId) {
        address _owner = _requireOwned(_tokenId);
        if (_owner != _msgSender()) {
            revert NotOwner(_tokenId);
        }
        _;
    }

    // Block minting unless phase is active
    modifier phaseActive(MintPhase _phase, uint8 _phaseId) {
        if (_phase == MintPhase.PUBLIC) {
            require(
                _publicMint.startTime <= block.timestamp && block.timestamp <= _publicMint.endTime, "Phase Inactive"
            );
        } else {
            uint256 phaseStartTime = mintPhases[_phaseId].startTime;
            uint256 phaseEndTime = mintPhases[_phaseId].endTime;
            require(phaseStartTime <= block.timestamp && block.timestamp < phaseEndTime, "Phase Inactive");
        }
        _;
    }

    modifier verifyPhaseId(uint8 _phaseId) {
        if (_phaseId >= MAX_PRESALE_LIMIT) {
            revert InvalidPhase(_phaseId);
        }
        _;
    }

    // Allows owner to pause minting at any phase.
    modifier isPaused() {
        if (paused) {
            revert SaleIsPaused();
        }
        _;
    }

    /**
     * @dev Enforce phase minting limit per address.
     */
    modifier limit(MintPhase _phase, address _to, uint256 _amount, uint8 _phaseId) {
        if (_phase == MintPhase.PUBLIC) {
            uint8 publicMintLimit = _publicMint.maxPerWallet;
            if (balanceOf(_to) + _amount > publicMintLimit) {
                revert PhaseLimitExceeded(publicMintLimit);
            }
        } else {
            uint8 phaseLimit = mintPhases[_phaseId].maxPerAddress;
            if (balanceOf(_to) + _amount > phaseLimit) {
                revert PhaseLimitExceeded(phaseLimit);
            }
        }
        _;
    }

    /**
     * @dev Control token trading
     * @notice Prevents trading of tokens until unlocked by creator.
     */
    modifier canTradeToken() {
        if (tradingLocked) {
            revert TradingLocked();
        }
        _;
    }

    //////////////////////////// USER MINTING FUNCTIONS //////////////////////////////////////

    /// @dev see {IERC721Collection-mintPublic}
    function mintPublic(uint256 _amount, address _to)
        external
        payable
        phaseActive(MintPhase.PUBLIC, 0)
        limit(MintPhase.PUBLIC, _to, _amount, 0)
        isPaused
        nonReentrant
    {
        if (!_canMint(_amount)) {
            revert SoldOut(maxSupply);
        }
        uint256 totalCost = _getCost(MintPhase.PUBLIC, 0, _amount);
        if (msg.value < totalCost) {
            revert InsufficientFunds(totalCost);
        }
        _mintNft(_to, _amount);
        _payout(MintPhase.PUBLIC, _amount, 0);
        emit Purchase(_to, _tokenId, _amount);
    }

    /**
     *
     * @dev see {IERC721Collection-whitelistMint}
     */
    function whitelistMint(bytes32[] memory _proof, uint8 _amount, uint8 _phaseId)
        external
        payable
        phaseActive(MintPhase.PRESALE, _phaseId)
        limit(MintPhase.PRESALE, _msgSender(), _amount, _phaseId)
        nonReentrant
        isPaused
    {
        if (!phaseCheck[_phaseId]) {
            revert InvalidPhase(_phaseId);
        }
        if (!_canMint(_amount)) {
            revert SoldOut(maxSupply);
        }
        uint256 totalCost = _getCost(MintPhase.PRESALE, _phaseId, _amount);
        if (msg.value < totalCost) {
            revert InsufficientFunds(totalCost);
        }
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_msgSender()))));
        bool whitelisted = _proof.verify(mintPhases[_phaseId].merkleRoot, leaf);
        if (!whitelisted) {
            revert NotWhitelisted(_msgSender());
        }
        _mintNft(_msgSender(), _amount);
        _payout(MintPhase.PRESALE, _amount, _phaseId);
    }

    ///////////////////////////// ADMIN/CREATOR MINTING FUNCTIONS //////////////////////////////

    /// @dev see {IERC721Collection-airdrop}
    function airdrop(address _to, uint256 _amount) external onlyOwner {
        if (!_canMint(_amount)) {
            revert SoldOut(maxSupply);
        }
        _mintNft(_to, _amount);
        emit Airdrop(_to, _tokenId, _amount);
    }

    ///@dev see {IERC721Collection-batchAirdrop}
    function batchAirdrop(address[] calldata _receipients, uint256 _amountPerAddress) external onlyOwner {
        if (_receipients.length > BATCH_MINT_LIMIT) {
            revert AmountTooHigh();
        }

        uint256 totalAmount = _amountPerAddress * _receipients.length;
        if (!_canMint(totalAmount)) {
            revert SoldOut(maxSupply);
        }
        for (uint256 i; i < _receipients.length; i++) {
            _mintNft(_receipients[i], _amountPerAddress);
        }
        emit BatchAirdrop(_receipients, _amountPerAddress);
    }

    //////////////////////////// PRESALE CONTROL ///////////////////////////////////////////

    /// @dev see {IERC721Collection-addPresalePhase}
    function addPresalePhase(PresalePhaseIn calldata _phase) external onlyOwner {
        if (mintPhases.length == MAX_PRESALE_LIMIT) {
            revert MaxPresaleLimitReached(MAX_PRESALE_LIMIT);
        }
        PresalePhase memory phase = PresalePhase({
            name: _phase.name,
            startTime: block.timestamp + _phase.startTime,
            endTime: block.timestamp + _phase.endTime,
            maxPerAddress: _phase.maxPerAddress,
            price: _phase.price,
            merkleRoot: _phase.merkleRoot,
            phaseId: phaseIds
        });

        mintPhases.push(phase);
        phaseCheck[phase.phaseId] = true;
        phaseIds += 1;
        emit AddPresalePhase(_phase.name, phase.phaseId);
    }

    /**
     * @dev Change the configuration for an added presale phase.
     * @param _phaseId is the phase to change config.
     * @param _newConfig is the configuration of the new phase.
     * Adds phase if phase does not exist and _phaseId does not exceed max allowed phase.
     *
     */
    function editPresalePhaseConfig(uint8 _phaseId, PresalePhaseIn memory _newConfig)
        external
        verifyPhaseId(_phaseId)
        onlyOwner
    {
        PresalePhase memory oldPhase = mintPhases[_phaseId];
        PresalePhase memory newPhase = PresalePhase({
            name: _newConfig.name,
            startTime: block.timestamp + _newConfig.startTime,
            endTime: block.timestamp + _newConfig.endTime,
            maxPerAddress: _newConfig.maxPerAddress,
            price: _newConfig.price,
            merkleRoot: _newConfig.merkleRoot,
            phaseId: _phaseId
        });
        if (phaseCheck[_phaseId]) {
            mintPhases[_phaseId] = newPhase;
        } else {
            mintPhases.push(newPhase);
            phaseCheck[_phaseId] = true;
        }
        emit EditPresaleConfig(oldPhase, newPhase);
    }

    /// @dev see {IERC721Collection-removePresalePhase}
    function removePresalePhase(uint8 _phaseId) external verifyPhaseId(_phaseId) onlyOwner {
        require(mintPhases[_phaseId].startTime > block.timestamp, "Phase Live");
        PresalePhase[] memory oldList = mintPhases;
        uint256 totalItems = oldList.length;
        phaseCheck[_phaseId] = false;
        delete mintPhases;
        for (uint8 i; i < totalItems; i++) {
            if (i < _phaseId) {
                mintPhases.push(oldList[i]);
            } else if (i > _phaseId) {
                uint8 newId = i - 1;
                oldList[i].phaseId = newId;
                mintPhases.push(oldList[i]);
            }
        }
    }

    ///////////////////////////////// COLLECTION SALE CONTROL ///////////////////////////

    // Pause mint process
    function pauseSale() external onlyOwner {
        paused = true;
        emit SalePaused();
    }

    // Resume mint process
    function resumeSale() external onlyOwner {
        paused = false;
        emit ResumeSale();
    }

    ///////////////////////////////////// SUPPLY CONTROL //////////////////////////////

    /**
     * @dev Reduce the collection supply
     * @param _newSupply is the new supply to be set
     */
    function reduceSupply(uint64 _newSupply) external onlyOwner {
        if (_newSupply < _totalMinted || _newSupply > maxSupply) {
            revert InvalidSupplyConfig();
        }
        maxSupply = _newSupply;
        emit SupplyReduced(_newSupply);
    }

    //////////////////////////////////////////////////////////////////////////////////

    // Withdraw funds from contract
    function withdraw(uint256 _amount) external onlyOwner nonReentrant {
        if (address(this).balance < _amount) {
            revert InsufficientFunds(_amount);
        }
        (bool success,) = payable(owner()).call{value: _amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit WithdrawFunds(_amount);
    }

    /**
     * @dev Allows creator to change royalty info.
     * @param receiver is the address of the new royalty fee receiver.
     * @param _royaltyFeeBps is the new royalty fee bps| 100bps= 1%
     */
    function setRoyaltyInfo(address receiver, uint256 _royaltyFeeBps) external onlyOwner {
        if (receiver == address(0)) {
            revert InvalidRoyaltyConfig(receiver, _royaltyFeeBps);
        }
        if (_royaltyFeeBps > MAX_ROYALTY_FEE) {
            revert InvalidRoyaltyConfig(receiver, _royaltyFeeBps);
        }
        royaltyFeeReceiver = receiver;
        royaltyFeeBps = _royaltyFeeBps;
    }

    /// @notice Allows creator to permit trading of nfts on secondary marketplaces.
    function unlockTrading() external onlyOwner {
        tradingLocked = false;
    }

    /// @dev sets the base URI of the collection to the original as defined by creator.
    function reveal(string memory _originalURI) external onlyOwner {
        revealed = true;
        _setBaseURI(_originalURI);
    }

    /// @dev see {ERC721-_burn}
    function burn(uint256 tokenId_) external tokenOwner(tokenId_) {
        _totalMinted -= 1;
        _burn(tokenId_);
    }

    /////////////////////////////// GENERAL GETTERS //////////////////////////////////////

    /**
     * @dev getter for presale phase data
     * @return array containing presale configuration for each added phase.
     */
    function getPresaleConfig() external view returns (PresalePhase[] memory) {
        return mintPhases;
    }

    /**
     * @dev getter for public mint data
     * @return public mint configuration. see {IERC721Collection-PublicMint}
     */
    function getPublicMintConfig() external view returns (PublicMint memory) {
        return _publicMint;
    }

    /**
     * @dev See {IERC2981-royaltyInfo}
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        address _tokenOwner = _requireOwned(tokenId);
        if (_tokenOwner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        return (royaltyFeeReceiver, salePrice.calculatePercentage(royaltyFeeBps));
    }

    /// @return max supply
    function totalSupply() external view returns (uint256) {
        return _totalMinted;
    }

    /**
     * @dev Calculates the share of the platform and creator from a minted token.
     * @param _phase is the mint phase of the token || Public or Presale.
     * @param _amount is the amount of tokens minted.
     * @param _phaseId is the phase id of the mint phase if it was minted on presale
     * @param _payee The party to be paid || Platform or Creator.
     * @return share of the platform or creator.
     * @notice The Platform share is calculated as the sum of mint fee for the amount of tokens minted and sales fee on each token.
     */
    function computeShare(MintPhase _phase, uint256 _amount, uint8 _phaseId, Payees _payee)
        public
        view
        returns (uint256 share)
    {
        if (_payee == Payees.PLATFORM) {
            if (_phase == MintPhase.PUBLIC) {
                uint256 _mintFee = mintFee * _amount;
                uint256 value = _publicMint.price * _amount;
                uint256 _salesFee = (value).calculatePercentage(SALES_FEE_BPS);
                share = _mintFee + _salesFee;
            } else {
                uint256 _mintFee = mintFee * _amount;
                uint256 _price = mintPhases[_phaseId].price;
                uint256 value = _price * _amount;
                uint256 _salesFee = (value).calculatePercentage(SALES_FEE_BPS);
                share = _mintFee + _salesFee;
            }
        } else {
            if (_phase == MintPhase.PUBLIC) {
                uint256 value = _publicMint.price * _amount;
                uint256 _salesFee = (value).calculatePercentage(SALES_FEE_BPS);
                share = value - _salesFee;
            } else {
                uint256 _price = mintPhases[_phaseId].price;
                uint256 value = _price * _amount;
                uint256 _salesFee = (value).calculatePercentage(SALES_FEE_BPS);
                share = value - _salesFee;
            }
        }
    }

    /**
     * @return uri for tokenID
     *  @notice If collection is unrevealed, base URI acts as concealer till collection is revealed.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory uri) {
        if (!revealed) {
            return baseURI;
        }
        uri = super.tokenURI(tokenId);
    }

    /// @return total nft minted
    function totalMinted() public view returns (uint64) {
        return _totalMinted;
    }

    ///////////////////////////////// TRANSFER CONTROL ////////////////////////////////////
    /**
     * @dev see {ERC721-safeTransferFrom}
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data)
        public
        override
        canTradeToken
    {
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    /// @dev see {ERC721-transferFrom}
    function transferFrom(address from, address to, uint256 tokenId) public override canTradeToken {
        super.transferFrom(from, to, tokenId);
    }

    /// @dev see {IERC165-supportsInterface}
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || interfaceId == type(IERC721Collection).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /////////////////////////////////////// INTERNALS ////////////////////////////////////////////////

    function _setBaseURI(string memory _uri) internal {
        baseURI = _uri;
    }

    ///@dev see {ERC721-_baseURI}
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Checks if a certain amount of token can be minted.
     * @param _amount is the amount of tokens to be minted.
     * @notice Ensures that minting _amount tokens does not cause the total minted tokens to exceed max supply.
     */
    function _canMint(uint256 _amount) internal view returns (bool) {
        if (_totalMinted + _amount > maxSupply) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * @dev Compute the total cost of minting a certain amount of tokens at a certain mint phase
     * @param _amount is the amount of tokens to be minted.
     * @return cost is the addition of sales price andf mint fee
     */
    function _getCost(MintPhase _phase, uint8 _phaseId, uint256 _amount) public view returns (uint256 cost) {
        if (_phase == MintPhase.PUBLIC) {
            return (_publicMint.price * _amount) + (mintFee * _amount);
        } else {
            return (mintPhases[_phaseId].price * _amount) + (mintFee * _amount);
        }
    }

    /**
     *
     * @dev Payout platform fee
     * @param _amount is the amount of nfts that was bought.
     * @param _phaseId is the mint phase in which the nft was bought.
     */
    function _payout(MintPhase _phase, uint256 _amount, uint8 _phaseId) internal {
        address platform = _FEE_RECEIPIENT;
        uint256 platformShare = computeShare(_phase, _amount, 0, Payees.PLATFORM);
        uint256 creatorShare = computeShare(_phase, _amount, _phaseId, Payees.CREATOR);
        (bool payPlatform,) = payable(platform).call{value: platformShare}("");
        if (!payPlatform) {
            revert PurchaseFailed();
        }
        (bool payCreator,) = payable(proceedCollector).call{value: creatorShare}("");
        if (!payCreator) {
            revert PurchaseFailed();
        }
    }

    /**
     * @dev Mint tokens to an address.
     * @param _to is the address of the receipient.
     * @param _amount is the amount of tokens to be minted.
     */
    function _mintNft(address _to, uint256 _amount) internal isPaused {
        uint64 tokenIdInc = _tokenId;
        uint64 totalMintedInc = _totalMinted;
        for (uint256 i; i < _amount; i++) {
            tokenIdInc += 1;
            totalMintedInc += 1;
            _safeMint(_to, tokenIdInc);
        }
        _tokenId = tokenIdInc;
        _totalMinted = totalMintedInc;
    }
}
