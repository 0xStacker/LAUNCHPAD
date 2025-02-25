// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IERC721Collection{

    error NotWhit~elisted(address _address);
    error InsufficientFunds(uint _cost);
    error SoldOut(uint maxSupply);
    error InvalidPhase(uint8 _phaseId);
    error PhaseLimitExceeded(uint _phaseLimit);
    error InvalidSupplyConfig();
    error PurchaseFailed();
    error NotCreator();
    error NotOwner();
    error SaleIsPaused();
    error WithdrawalFailed();
    error MaxPhaseLimit();
    error AmountTooHigh();


    event AddPresalePhase(string _phaseName, uint8 _phaseId);
    event RemovePresalePhase(string _phaseName, uint8 _phaseId);
    event BatchAirdrop(address[] _receipients, uint _amount);
    event Purchase(address indexed _buyer, uint _tokenId, uint _amount);
    event Airdrop(address indexed _to, uint _tokenId, uint _amount);
    event WithdrawFunds(uint _amount);
    event SetPhase(uint _phaseCount);
    event SupplyReduced(uint64 _newSupply);
    event ResumeSale();
    event PublicMintEnabled();
    event SalePaused();
    event PublicMintDisabled();

}