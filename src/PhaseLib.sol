// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library Phase{
    /**
    * @dev Holds mint details for the public/general mint
    */
    struct PublicMint{
        uint startTime;
        uint endTime;
        uint price;
        uint maxPerWallet;
    }
    
    // Holds data for merkle tree based whitelist phase.
    
    struct PresalePhaseIn{
        uint8 maxPerAddress;
        string name;
        uint price;
        uint startTime;
        uint endTime;
        bytes32 merkleRoot;
    }

    struct PresalePhase{
        uint8 maxPerAddress;
        string name;
        uint price;
        uint startTime;
        uint endTime;
        bytes32 merkleRoot;
        uint phaseId;
    }


    function getId(PresalePhaseIn memory phase, uint8 _id) external pure returns (PresalePhase memory){
        PresalePhase memory _phase = PresalePhase({
            maxPerAddress : phase.maxPerAddress,
            name: phase.name,
            price: phase.price,
            startTime: phase.startTime,
            endTime: phase.endTime,
            merkleRoot: phase.merkleRoot,
            phaseId : _id
        });

        return _phase;
    } 
}