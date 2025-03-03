// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";
import {IERC721Collection} from "./IERC721Collection.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";

/**
 * @dev Implementation of an ERC721 drop.
 * @author 0xstacker "github.com/0xStacker"
 */
contract Drop is ERC721, IERC721Collection, ReentrancyGuard {
    /// @dev Maximum number of presale phases that can be added.
    uint8 constant PHASELIMIT = 5;

    /// @dev Maximum number of tokens that can be minted in a single transaction.
    uint8 constant BATCH_MINT_LIMIT = 8;

    /// @dev Collection owner
    address public immutable owner;

    /// @dev Platform fee receipient
    address private immutable _FEE_RECEIPIENT;

    /// @dev If set to true, pauses minting of tokens.
    bool public paused;

    /// @dev If set to true, prevents trading of tokens until minting is complete.
    bool public lockedTillMintOut;

    /// @notice Maximum supply of collection
    uint64 public maxSupply;

    /// @notice Current token id
    uint64 private _tokenId;

    /// @notice Total number of minted tokens
    uint64 private _totalMinted;

    // uint private constant royalty;

    string baseURI;

    /**
     * @dev Platform mint fee
     */
    uint256 public immutable mintFee;

    /// @dev public mint configuration
    PublicMint private _publicMint;

    // Sequential phase identities
    uint8 internal phaseIds;

    /**
     * @dev presale mint phases.
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
     * @param _owner is the address of the collection owner
     * @param _publicMintConfig is the public mint configuration.
     * @param _mintFee is the platform mint fee
     * @param _baseUri is the base uri for the collection.
     * @param _feeReceipient is the platform fee receipient.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint64 _maxSupply,
        PublicMint memory _publicMintConfig,
        uint256 _mintFee,
        address _owner,
        string memory _baseUri,
        address _feeReceipient,
        bool _lockedTillMintOut
    ) ERC721(_name, _symbol) ReentrancyGuard() {
        maxSupply = _maxSupply;
        // Ensure that owner is not a contract
        require(_owner.code.length == 0 && _owner != address(0), "Invalid Adress");
        owner = _owner;

        if (_feeReceipient == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        _FEE_RECEIPIENT = _feeReceipient;
        mintFee = _mintFee;
        _publicMint = _publicMintConfig;
        baseURI = _baseUri;
        lockedTillMintOut = _lockedTillMintOut;
    }

    receive() external payable {}

    fallback() external payable {}

    // Enforce Creator priviledges
    modifier onlyCreator() {
        if (_msgSender() != owner) {
            revert NotCreator();
        }
        _;
    }

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
     * @dev Control token treading
     * @notice Prevents trading of tokens until minting is complete if {lockedTillMintOut} is set to true.
     */
    modifier canTradeToken() {
        bool mintedOut = maxSupply == _totalMinted;
        if (lockedTillMintOut && !mintedOut) {
            revert TradingLocked();
        }
        _;
    }

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
        _payout(_amount, 0);
        emit Purchase(_to, _tokenId, _amount);
    }

    /// @dev see {IERC721Collection-addPresalePhase}
    function addPresalePhase(PresalePhaseIn calldata _phase) external onlyCreator {
        PresalePhase memory phase = PresalePhase({
            name: _phase.name,
            startTime: block.timestamp + _phase.startTime,
            endTime: block.timestamp + _phase.endTime,
            maxPerAddress: _phase.maxPerAddress,
            price: _phase.price,
            merkleRoot: _phase.merkleRoot,
            phaseId: phaseIds
        });

        mintPhases[phase.phaseId] = phase;
        mintPhases[phase.phaseId].startTime = phase.startTime + block.timestamp;
        mintPhases[phase.phaseId].endTime = phase.endTime + block.timestamp;
        phaseCheck[phase.phaseId] = true;
        _returnablePhases.push(phase);
        phaseIds += 1;
        emit AddPresalePhase(_phase.name, phase.phaseId);
    }

    /// @dev see {IERC721Collection-reduceSupply}

    function reduceSupply(uint64 _newSupply) external onlyCreator {
        if (_newSupply < _totalMinted || _newSupply > maxSupply) {
            revert InvalidSupplyConfig();
        }
        maxSupply = _newSupply;
        emit SupplyReduced(_newSupply);
    }

    // getter for presale phase data
    function getPresaleConfig() external view returns (PresalePhase[] memory) {
        return _returnablePhases;
    }

    // getter for public mint data
    function getPublicMintConfig() external view returns (PublicMint memory) {
        return _publicMint;
    }

    /// @dev see {IERC721Collection-airdrop}
    function airdrop(address _to, uint256 _amount) external onlyCreator {
        if (!_canMint(_amount)) {
            revert SoldOut(maxSupply);
        }
        _mintNft(_to, _amount);
        emit Airdrop(_to, _tokenId, _amount);
    }

    ///@dev see {IERC721Collection-batchAirdrop}
    function batchAirdrop(address[] calldata _receipients, uint256 _amountPerAddress) external onlyCreator {
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

    // Pause mint process
    function pauseSale() external onlyCreator {
        paused = true;
        emit SalePaused();
    }

    // Resume mint process
    function resumeSale() external onlyCreator {
        paused = false;
        emit ResumeSale();
    }

    // Withdraw funds from contract
    function withdraw(uint256 _amount) external onlyCreator nonReentrant {
        if (address(this).balance < _amount) {
            revert InsufficientFunds(_amount);
        }
        (bool success,) = payable(owner).call{value: _amount}("");
        if (!success) {
            revert WithdrawalFailed();
        }
        emit WithdrawFunds(_amount);
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
        _payout(_amount, _phaseId);
    }

    /// @dev see {ERC721-_burn}

    function burn(uint256 tokenId_) external tokenOwner(tokenId_) {
        _burn(tokenId_);
    }

    // total supply
    function supply() external view returns (uint256) {
        return maxSupply;
    }

    function setBaseURI(string memory _uri) external onlyCreator {
        baseURI = _uri;
    }

    /**
     *
     * @dev see {IERC721Collection-contractOwner}
     */
    function contractOwner() external view returns (address) {
        return owner;
    }

    function computeShare(uint256 _amount, uint8 _phaseId, Payees _payee) public view returns (uint256 share) {
        if (_payee == Payees.PLATFORM) {
            share = mintFee * _amount;
        } else {
            uint256 _price = mintPhases[_phaseId].price;
            share = _price * _amount;
        }
    }
    /**
     *
     * @dev see {ERC721-_baseURI}
     */

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
     * @dev Compute the cost of minting a certain amount of tokens.
     * @param _amount is the amount of tokens to be minted.
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
    function _payout(uint256 _amount, uint8 _phaseId) internal {
        address platform = _FEE_RECEIPIENT;
        address creator = owner;
        uint256 platformShare = computeShare(_amount, 0, Payees.PLATFORM);
        uint256 creatorShare = computeShare(_amount, _phaseId, Payees.CREATOR);
        (bool payPlatform,) = payable(platform).call{value: platformShare}("");
        if (!payPlatform) {
            revert PurchaseFailed();
        }
        (bool payCreator,) = payable(creator).call{value: creatorShare}("");
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

    function totalMinted() public view returns (uint64) {
        return _totalMinted;
    }

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
}
