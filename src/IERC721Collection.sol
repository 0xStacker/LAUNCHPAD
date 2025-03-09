// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721Collection {
    /// @dev Parties to be paid.
    enum Payees {
        PLATFORM,
        CREATOR
    }

    enum MintPhase {
        PUBLIC,
        PRESALE
    }

    ///@dev Collection details
    struct Collection {
        bool tradingLocked;
        bool revealed;
        uint64 maxSupply;
        address owner;
        address proceedCollector;
        address royaltyReceipient;
        string name;
        string symbol;
        string baseURI;
        uint256 royaltyFeeBps;
    }

    /// @dev Platform info.
    struct Platform {
        address feeReceipient;
        uint256 mintFee;
        uint256 salesFeeBps;
    }

    /// @dev Holds the input data for presale configuration
    struct PresalePhaseIn {
        uint8 maxPerAddress;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bytes32 merkleRoot;
    }

    /**
     * @dev Holds the details of the public/general mint phase
     */
    struct PublicMint {
        uint8 maxPerWallet;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
    }

    /**
     * @dev Holds the deta of a presale phase after it has been assigned an identifier
     */
    struct PresalePhase {
        uint8 maxPerAddress;
        uint8 phaseId;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bytes32 merkleRoot;
    }

    /// @dev Thrown when a user is not whitelisted for a presale phase
    error NotWhitelisted(address _address);

    /// @dev Thrown when a user tries to trade an NFT while collection is not sold out yet.
    error TradingLocked();

    /// @dev Thrown when a user does not send enough ether to mint an amount of NFTs
    error InsufficientFunds(uint256 _cost);

    /// @dev Thrown when a user tries to mint after collection has bee sold out
    error SoldOut(uint256 maxSupply);

    /// @dev Thrown when a user tries to mint from a phase that is not in the mint configuration
    error InvalidPhase(uint8 _phaseId);

    /// @dev Thrown when a user tries to mint more than the amount they're allowed to mint from a particular phase.
    error PhaseLimitExceeded(uint8 _phaseLimit);

    /// @dev Thrown when creator tries to add more presale phase than permitted.
    error MaxPresaleLimitReached(uint8 _maxLimit);

    /**
     * @dev Thrown when creator tries to reduce supply to an amount that's either;
     * - less than the total minted tokens or less than the total supply.
     * - greater than initially set max supply.
     */
    error InvalidSupplyConfig();

    /// @dev Thrown whenever a purchase is attempted and fails.
    error PurchaseFailed();

    /// @dev Thrown when a user tries to execute a function that is only allowed to be called by the nft token owner.
    error NotOwner(uint256 _tokenId);

    /// @dev Thrown whenever a mint is attempted while sale is paused.
    error SaleIsPaused();

    /// @dev Thrown when creator attempts to withdraw funds from the contract and the withdrawal fails.
    error WithdrawalFailed();

    /// @dev Thrown when creator tries to airdrop a set number of people and the number exceeds the allowed limit.
    error AmountTooHigh();

    /// @dev Thrown when creator tries to set royalty receipient to an invalid address or to a value greater than allowed.
    error InvalidRoyaltyConfig(address receiver, uint256 _royaltyFeeBps);

    /// @dev Emitted after adding a new presale phase to the collection.
    event AddPresalePhase(string _phaseName, uint8 _phaseId);

    /// @dev Emitted after a successful batch Airdrop.
    event BatchAirdrop(address[] _receipients, uint256 _amount);

    /// @dev Emitted after a successful Purchase.
    event Purchase(address indexed _buyer, uint256 _tokenId, uint256 _amount);

    /// @dev Emitted after a successful Airdrop.
    event Airdrop(address indexed _to, uint256 _tokenId, uint256 _amount);

    /// @dev Emitted after funds are withdrawn from contract.
    event WithdrawFunds(uint256 _amount);

    ///@dev Emitted after setting presale Phase.
    event SetPhase(uint256 _phaseCount);

    /// @dev Emitted when the collection supply is reduced.
    event SupplyReduced(uint64 _newSupply);

    /// @dev Emitted when the sale is resumed.
    event ResumeSale();

    /// @dev Emitted when the sale is paused.
    event SalePaused();

    /// @dev Emitted when the configuration of a presale phase is changed.
    event EditPresaleConfig(PresalePhase _oldConfig, PresalePhase _newConfig);

    /// @dev Emitted when creator removes a presale phase.
    event RemovePresalePhase(uint8 _phaseId, string _name);

    /**
     * @dev Public minting function.
     * @param _amount is the amount of nfts to mint.
     * @param _to is the address to mint the tokens to.
     * @notice can only mint when public sale has started and the minting process is not paused by the creator.
     * @notice minting is limited to the maximum amounts allowed on the public mint phase.
     */
    function mintPublic(uint256 _amount, address _to) external payable;

    /**
     * @dev adds new presale phase for contract
     * @param _phase is the new phase to be added
     * @notice phases are identified sequentially using numbers, starting from 1.
     */
    function addPresalePhase(PresalePhaseIn calldata _phase) external;

    /**
     * @dev Remove a presale phase from the collection.
     * @param _phaseId is the phase to be removed.
     * @notice Only possible if phase is not already live.
     */
    function removePresalePhase(uint8 _phaseId) external;

    /**
     * @dev Returns an array containing details for each presale phase
     */
    function getPresaleConfig() external view returns (PresalePhase[] memory);

    /**
     * @dev Allows creator to airdrop NFTs to an account
     * @param _to is the address of the receipeient
     * @param _amount is the amount of NFTs to be airdropped
     * Ensures amount of tokens to be minted does not exceed MAX_SUPPLY
     */
    function airdrop(address _to, uint256 _amount) external;

    /**
     * @dev Allows the creator to airdrop NFT to multiple addresses at once.
     * @param _receipients is the list of accounts to mint NFT for.
     * @param _amountPerAddress is the amount of tokens to be minted per addresses.
     * Ensures total amount of NFT to be minted does not exceed MAX_SUPPLY.
     *
     */
    function batchAirdrop(address[] calldata _receipients, uint256 _amountPerAddress) external;

    /**
     * @dev Check the whitelist status of an account based on merkle proof.
     * @param _proof is a merkle proof to check for verification.
     * @param _amount is the amount of tokens to be minted.
     * @param _phaseId is the presale phase the user is attempting to mint for.
     * @notice If phase is not active, function reverts.
     * @notice If amount exceeds the phase limit, function reverts.
     */
    function whitelistMint(bytes32[] memory _proof, uint8 _amount, uint8 _phaseId) external payable;
}
