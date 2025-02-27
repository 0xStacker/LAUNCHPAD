// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721Collection {
    enum Payees {
        PLATFORM,
        CREATOR
    }

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
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint8 maxPerWallet;
    }

    /**
     * @dev Holds the details of a presale phase
     */
    struct PresalePhase {
        uint8 maxPerAddress;
        string name;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bytes32 merkleRoot;
        uint256 phaseId;
    }

    error NotWhitelisted(address _address);
    error InsufficientFunds(uint256 _cost);
    error SoldOut(uint256 maxSupply);
    error InvalidPhase(uint8 _phaseId);
    error PhaseLimitExceeded(uint8 _phaseLimit);
    error InvalidSupplyConfig();
    error PurchaseFailed();
    error NotCreator();
    error NotOwner();
    error SaleIsPaused();
    error WithdrawalFailed();
    error MaxPhaseLimit();
    error AmountTooHigh();

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
     *
     * @dev Reduce the collection supply
     * @param _newSupply is the new supply to be set
     * Ensures that the new supply is not less than the total minted tokens
     *
     */
    function reduceSupply(uint64 _newSupply) external;

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
     * @notice If amount exceeds the maximum allowed to be minted per walllet, function reverts.
     */
    function whitelistMint(bytes32[] memory _proof, uint8 _amount, uint8 _phaseId) external payable;

    /**
     * '
     * @dev Get the creator address
     */
    function contractOwner() external view returns (address);
}
