// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

import "../token/ERC20Burnable.sol";

import "../utils/Ownable.sol";

contract Dagora is IArbitrable, Ownable {

    /* 2 decimal plates for percentage */
    uint public constant INVERSE_BASIS_POINT = 10000;

    uint8 constant AMOUNT_OF_CHOICES = 2;

    enum Party {Prosecution, Defendant}
    enum DisputeType {Report, Order}
    enum RulingOptions {NoRuling, ProsecutionWins, DefendantWins}
    enum DisputeStatus {NoDispute, WaitingProsecution, WaitingDefendant, DisputeCreated, Resolved}
    enum Status {Invalid, WaitingConfirmation, InDispute, Finished}

    struct Listing {
        bytes32 ipfsHash;
        address payable seller;
        address payable stakeOwner;
        uint stakedAmount;
        uint commissionPercentage;
        uint warrantyTimeout;
        uint expiration;
    }

    struct Order {
        bytes32 listingHash;
        address payable buyer;
        address payable commissioner;
        ERC20 token;
        uint total;
        uint shippingCost;
        uint offerExpiration;
        uint confirmationTimeout;
    }

    struct Transaction {
        bytes32 orderHash;

        uint lastInteraction;

        Status status;
    }

    struct Seller {
        // The amount of tokens the contract holds for this seller.
        uint balance;
        /* Total number of tokens the seller can loose in disputes they are. 
         * Those tokens are locked. Note that we can have lockedTokens > balance but it should
         * be statistically unlikely and does not pose issues.*/
        uint lockedTokens;
    }

    /* An ECDSA signature. */
    struct Sig {
        /* v parameter */
        uint8 v;
        /* r parameter */
        bytes32 r;
        /* s parameter */
        bytes32 s;
    }

    struct RunningDispute {
        address payable prosecution;
        address payable defendant;
        uint amount;
        ERC20 token;
        uint prosecutionFee;
        uint defendantFee;
        DisputeType disputeType;
        uint lastInteraction;
        uint metaEvidenceId;
        DisputeStatus status;
    }

    event ListingCancelled (bytes32 indexed hash);

    event HasToPayFee (bytes32 indexed _hash, Party _party);

    mapping (address => Seller) public sellers;
    /* Cancelled / finalized listings and orders, by hash. */
    mapping(bytes32 => bool) public cancelledOrFinalized;
    /* Orders and listings verified by on-chain approval (alternative to ECDSA signatures so that smart contracts can place orders and listings directly). */
    mapping(bytes32 => bool) public approvedHashes;

    mapping (bytes32 => RunningDispute) public disputes; // Listing Hash to Dispute
    mapping (uint => bytes32) public disputeIDtoHash;

    Arbitrator public arbitrator; // Address of the arbitrator contract.
    bytes public reportExtraData; // Extra data to set up the arbitration.
    bytes public orderExtraData; // Extra data to set up the arbitration.
    uint public feeTimeout; /* Time in seconds a party can take to pay arbitration
                             * fees before being considered unresponding and lose the dispute.*/

    mapping(address => bool) public contracts;

    ERC20Burnable public marketToken;
    uint public metaEvidenceCount;
    string public ipfsDomain;

    constructor(address _arbitrator,
                address _token,
                uint _feeTimeout,
                bytes memory _reportExtraData,
                bytes memory _orderExtraData,
                string memory _ipfsDomain)
        Ownable()
        public
    {
        arbitrator = Arbitrator(_arbitrator);
        marketToken = ERC20Burnable(_token);
        feeTimeout = _feeTimeout;
        reportExtraData = _reportExtraData;
        orderExtraData = _orderExtraData;
        ipfsDomain = _ipfsDomain;
    }

    function grantAuthentication (address addr)
        public
        onlyOwner
    {
        require(!contracts[addr]);
        contracts[addr] = true;
    }

    function revokeAuthentication (address addr)
        public
        onlyOwner
    {
        contracts[addr] = false;
    }

    function depositTokens(uint value)
        public
    {
        require(marketToken.transferFrom(msg.sender, address(this), value));
        sellers[msg.sender].balance += value;
        // TODO EMIT TOKENS DEPOSIT
    }

    function withdrawTokens(uint value)
        public
    {
        Seller storage seller = sellers[msg.sender];
        require(seller.balance - seller.lockedTokens >= value, "You don't have enoght tokens");
        require(marketToken.transferFrom(msg.sender, address(this), value));
        sellers[msg.sender].balance -= value;
        // TODO EMIT TOKENS WITHDRAW
    }

    function approveListing(Listing memory _listing)
        public returns (bool)
    {
        /* CHECKS */
        /* Assert sender is authorized to approve listing. */
        require(msg.sender == _listing.stakeOwner, "Sender is not listing signer");
        require(sellers[msg.sender].balance >= _listing.stakedAmount, "You don't have enoght funds");
        /* Calculate listing hash. */
        bytes32 hash = hashListingToSign(_listing);
        /* Assert listing has not already been approved. */
        require(!approvedHashes[hash], "Already approved");
        /* EFFECTS */
        /* Mark listing as approved. */
        approvedHashes[hash] = true;
        // EMIT LISTING APPROVED
        return true;
    }

    function cancelListing(Listing memory _listing, Sig memory sig)
        internal
    {
        /* CHECKS */

        /* Calculate listing hash. */
        bytes32 hash = requireValidListing(_listing, sig);

        /* Assert sender is authorized to cancel listing. */
        require(msg.sender == _listing.stakeOwner || msg.sender == _listing.seller);
  
        /* EFFECTS */
      
        /* Mark listing as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;

        /* Log cancel event. */
        emit ListingCancelled(hash);
    }

    function report(Listing memory _listing, Sig memory sig)
        public
        payable
        returns (bytes32 hash)
    {
        /* CHECKS */
        hash = requireValidListing(_listing, sig);
        require(disputes[hash].status == DisputeStatus.NoDispute, "Listing has already been reported");
        require(msg.sender != _listing.stakeOwner, "You can't report yourself. Use cancelListing()");
        uint arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(msg.value >= arbitrationCost, "Value must be greater than arbitrationCost");
        Seller storage prosecution = sellers[msg.sender];
        uint availableBalance = prosecution.balance - prosecution.lockedTokens;
        if(availableBalance < _listing.stakedAmount) {
            require(marketToken.transferFrom(msg.sender, address(this), _listing.stakedAmount - availableBalance), "Unable to transfer tokens");
            prosecution.balance += _listing.stakedAmount - availableBalance;
        }
        /* EFFECTS */
        Seller storage defendant = sellers[_listing.stakeOwner];
        prosecution.lockedTokens += _listing.stakedAmount;
        defendant.lockedTokens += _listing.stakedAmount;
        RunningDispute storage dispute = _createDispute(hash,
                                                        msg.sender,
                                                        _listing.stakeOwner,
                                                        _listing.stakedAmount,
                                                        marketToken,
                                                        msg.value,
                                                        DisputeType.Report);
        emit MetaEvidence(dispute.metaEvidenceId, string(abi.encodePacked(ipfsDomain, _listing.ipfsHash)));
       
    }

    function _createDispute(bytes32 hash,
                            address payable prosecution,
                            address payable defendant,
                            uint amount, ERC20 token,
                            uint prosecutionFee,
                            DisputeType disputeType)
        internal
        returns(RunningDispute storage dispute)
    {
        dispute = disputes[hash];
        dispute.prosecution = prosecution;
        dispute.defendant = defendant;
        dispute.amount = amount;
        dispute.prosecutionFee += prosecutionFee;
        dispute.disputeType = disputeType;
        /* We know the token is market token, save gas*/
        if (disputeType == DisputeType.Report)
            dispute.token = token;
        dispute.status = DisputeStatus.WaitingDefendant;
        dispute.lastInteraction = now;
        dispute.metaEvidenceId = metaEvidenceCount++;
        emit HasToPayFee(hash, Party.Defendant);
    }

    function disputeTimeOut(bytes32 hash)
        public
    {
        RunningDispute storage dispute = disputes[hash];
        require(DisputeStatus.NoDispute < dispute.status && dispute.status < DisputeStatus.DisputeCreated, "Dispute is not waiting for any party.");
        require(now - dispute.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");
        bool success;
        if (dispute.prosecutionFee != 0) {
            uint prosecutionFee = dispute.prosecutionFee;
            dispute.prosecutionFee = 0;
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
        }
        if (dispute.defendantFee != 0) {
            uint defendantFee = dispute.defendantFee;
            dispute.defendantFee = 0;
            (success, ) = dispute.defendant.call{value: defendantFee}("");
        }
        if(dispute.status == DisputeStatus.WaitingDefendant) {
            executeReportRuling(dispute, uint(RulingOptions.ProsecutionWins));
        } else {
            executeReportRuling(dispute, uint(RulingOptions.DefendantWins));
        }
    }

    function payArbitrationFee(bytes32 hash)
        public
        payable
    {
        RunningDispute storage dispute = disputes[hash];
        uint arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(DisputeStatus.NoDispute < dispute.status && dispute.status < DisputeStatus.DisputeCreated, "Dispute has already been created.");
        require(msg.sender == dispute.prosecution || msg.sender == dispute.defendant, "The caller must be the sender.");

        if (msg.sender == dispute.prosecution) {
            dispute.prosecutionFee += msg.value;
            require(dispute.prosecutionFee >= arbitrationCost, "The prosecution fee must cover arbitration costs.");
            dispute.lastInteraction = now;
            if (dispute.defendantFee < arbitrationCost) {
                dispute.status = DisputeStatus.WaitingDefendant;
                emit HasToPayFee(hash, Party.Defendant);
            } else { // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost, reportExtraData);
            }
        } else {
            dispute.defendantFee += msg.value;
            require(dispute.defendantFee >= arbitrationCost, "The prosecution fee must cover arbitration costs.");
            dispute.lastInteraction = now;
            if (dispute.prosecutionFee < arbitrationCost) {
                dispute.status = DisputeStatus.WaitingProsecution;
                emit HasToPayFee(hash, Party.Prosecution);
            } else { // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost, reportExtraData);
            }
        }
    }

    function raiseDispute(bytes32 hash, uint _arbitrationCost, bytes memory extraData) 
        internal
    {
        RunningDispute storage dispute = disputes[hash];
        dispute.status = DisputeStatus.DisputeCreated;
        uint disputeId = arbitrator.createDispute{value: _arbitrationCost}(AMOUNT_OF_CHOICES, extraData);
        disputeIDtoHash[disputeId] = hash;
        emit Dispute(arbitrator, disputeId, dispute.metaEvidenceId, dispute.metaEvidenceId);

        // Refund sender if it overpaid.
        bool success;
        if (dispute.prosecutionFee > _arbitrationCost) {
            uint extraFeeProsecution = dispute.prosecutionFee - _arbitrationCost;
            dispute.prosecutionFee = _arbitrationCost;
            (success, ) = dispute.prosecution.call{value: extraFeeProsecution}("");
        }

        // Refund receiver if it overpaid.
        if (dispute.defendantFee > _arbitrationCost) {
            uint extraFeeDefendant = dispute.defendantFee - _arbitrationCost;
            dispute.defendantFee = _arbitrationCost;
            (success, ) = dispute.defendant.call{value: extraFeeDefendant}("");
        }
    }

    function rule(uint _disputeID, uint _ruling)
        public
        override
    {
        emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);
        bytes32 hash = disputeIDtoHash[_disputeID];
        RunningDispute storage dispute = disputes[hash];
        if (dispute.disputeType == DisputeType.Report) {
            executeReportRuling(dispute, _ruling);
        } else {
            executeOrderRuling(dispute, _ruling);
        }
    }

    function executeOrderRuling(RunningDispute storage dispute, uint _ruling) 
        internal
    {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint amount = dispute.amount;
        uint prosecutionFee = dispute.prosecutionFee;
        uint defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = DisputeStatus.Resolved;
        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint(RulingOptions.ProsecutionWins)) {
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
            require(dispute.token.transfer(dispute.prosecution, amount), "The `transfer` function must not fail.");
        } else if (_ruling == uint(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{value: defendantFee}("");
            require(dispute.token.transfer(dispute.defendant, amount), "The `transfer` function must not fail.");
        } else {
            // `senderFee` and `receiverFee` are equal to the arbitration cost.
            uint splitArbitrationFee = prosecutionFee / 2;
            /* Give 1 wei more to defendant in case of even number */
            (success, ) = dispute.defendant.call{value: defendantFee - splitArbitrationFee}("");
            (success, ) = dispute.prosecution.call{value: splitArbitrationFee}("");
            uint half = amount / 2;
            require(dispute.token.transfer(dispute.defendant, amount - half), "The `transfer` function must not fail.");
            require(dispute.token.transfer(dispute.prosecution, half), "The `transfer` function must not fail.");
        }
    }

    function executeReportRuling(RunningDispute storage dispute, uint _ruling) 
        internal
    {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint amount = dispute.amount;
        uint prosecutionFee = dispute.prosecutionFee;
        uint defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = DisputeStatus.Resolved;
        sellers[dispute.prosecution].lockedTokens -= dispute.amount;
        sellers[dispute.defendant].lockedTokens -= dispute.amount;
        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint(RulingOptions.ProsecutionWins)) {
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
            sellers[dispute.defendant].balance -= amount;
            sellers[dispute.prosecution].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else if (_ruling == uint(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{value: defendantFee}("");
            sellers[dispute.prosecution].balance -= amount;
            sellers[dispute.defendant].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else {
            // `senderFee` and `receiverFee` are equal to the arbitration cost.
            uint splitArbitrationFee = prosecutionFee / 2;
            (success, ) = dispute.defendant.call{value: defendantFee - splitArbitrationFee}("");
            (success, ) = dispute.prosecution.call{value: splitArbitrationFee}("");
            // In the case of an uneven token amount, one basic token unit can be burnt.
            sellers[dispute.prosecution].balance -= amount / 2;
            sellers[dispute.defendant].balance -= amount / 2;
            
        }
    }

    function validateListing(bytes32 hash, Listing memory _listing, Sig memory sig)
        internal
        view
        returns (bool)
    {
        /* Listing has expired */
        if (_listing.expiration != 0 && now > _listing.expiration) {
            return false;
        }

        /* Stake owner must have enough tokens */
        if (sellers[_listing.stakeOwner].balance - sellers[_listing.stakeOwner].lockedTokens < _listing.stakedAmount) {
            return false;
        }
        
        /* Listing must have not been canceled or already filled. */
        if (cancelledOrFinalized[hash]) {
            return false;
        }

        /* Listing authentication. Listing must be either:
        /* (a) previously approved */
        if (approvedHashes[hash]) {
            return true;
        }

        /* or (b) ECDSA-signed by stakeOwner. */
        if (ecrecover(hash, sig.v, sig.r, sig.s) == _listing.stakeOwner) {
            return true;
        }

        return false;
    }

    function hashListing(Listing memory listing)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(abi.encodePacked(listing.ipfsHash,
                                            listing.seller,
                                            listing.stakeOwner,
                                            listing.stakedAmount,
                                            listing.commissionPercentage,
                                            listing.warrantyTimeout,
                                            listing.expiration));
        return hash;
    }

    function hashToSign(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function hashListingToSign(Listing memory listing)
        internal
        pure
        returns (bytes32)
    {
        return hashToSign(hashListing(listing));
    }

    function requireValidListing(Listing memory listing, Sig memory sig)
        internal
        view
        returns (bytes32)
    {
        bytes32 hash = hashListingToSign(listing);
        require(validateListing(hash, listing, sig), "Invalid listing");
        return hash;
    }
}