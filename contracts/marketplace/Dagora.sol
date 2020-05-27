// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

import "../token/ERC20Burnable.sol";

contract Dagora is IArbitrable {

    uint8 constant AMOUNT_OF_CHOICES = 2;

    enum Party {Prosecution, Defendant}
    enum DisputeType {Report, Order}
    enum RulingOptions {NoRuling, ProsecutionWins, DefendantWins}
    enum Status {NoDispute, WaitingProsecution, WaitingDefendant, DisputeCreated, Resolved}

    struct Listing {
        bytes32 ipfsHash;
        address seller;
        address payable stakeOwner;
        uint stakedAmount;
        uint commissionPercentage;
        uint creationTimestamp;
        uint warrantyTimeout;
        uint expiration;
    }

    struct Seller {
        uint balance;      // The amount of tokens the contract holds for this seller.
        // Total number of tokens the seller can loose in disputes they are drawn in. Those tokens are locked. Note that we can have atStake > balance but it should be statistically unlikely and does not pose issues.
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
        Status status;
    }

    event ListingCancelled          (bytes32 indexed hash);

    event HasToPayFee(bytes32 indexed _hash, Party _party);

    mapping (address => Seller) public sellers;
    /* Cancelled / finalized orders, by hash. */
    mapping(bytes32 => bool) public cancelledOrFinalized;
    /* Orders verified by on-chain approval (alternative to ECDSA signatures so that smart contracts can place orders directly). */
    mapping(bytes32 => bool) public approvedOrders;

    mapping (bytes32 => RunningDispute) public disputes; // Listing Hash to Dispute
    mapping (uint => bytes32) public disputeIDtoHash;

    Arbitrator public arbitrator; // Address of the arbitrator contract.
    bytes public reportExtraData; // Extra data to set up the arbitration.
    bytes public orderExtraData; // Extra data to set up the arbitration.
    uint public feeTimeout; /* Time in seconds a party can take to pay arbitration
     fees before being considered unresponding and lose the dispute.*/
    uint public reportTimeout; // Time in seconds a party can report

    ERC20Burnable public marketToken;
    uint public metaEvidenceCount;
    string public ipfsDomain;

    constructor(address _arbitrator,
                address _token,
                uint _reportTimeout,
                uint _feeTimeout,
                bytes memory _reportExtraData,
                bytes memory _orderExtraData,
                string memory _ipfsDomain) public {
        arbitrator = Arbitrator(_arbitrator);
        marketToken = ERC20Burnable(_token);
        reportTimeout = _reportTimeout;
        feeTimeout = _feeTimeout;
        reportExtraData = _reportExtraData;
        orderExtraData = _orderExtraData;
        ipfsDomain = _ipfsDomain;
    }

    function depositTokens(uint value)
        public
    {
        require(marketToken.transferFrom(msg.sender, address(this), value));
        sellers[msg.sender].balance += value;
    }

    function withdrawTokens(uint value)
        public
    {
        Seller storage seller = sellers[msg.sender];
        require(seller.balance - seller.lockedTokens >= value, "You don't have enoght tokens");
        sellers[msg.sender].balance -= value;
        require(marketToken.transferFrom(msg.sender, address(this), value));
    }

    function approveListing(Listing memory _listing)
        public returns (bool)
    {
        /* CHECKS */
        /* Assert sender is authorized to approve order. */
        require(msg.sender == _listing.stakeOwner, "Sender is not listing signer");
        require(sellers[msg.sender].balance >= _listing.stakedAmount, "You don't have enoght funds");
        /* Calculate order hash. */
        bytes32 hash = hashListingToSign(_listing);
        /* Assert order has not already been approved. */
        require(!approvedOrders[hash], "Already approved");
        /* EFFECTS */
        /* Mark order as approved. */
        approvedOrders[hash] = true;
        return true;
    }

    function cancelListing(Listing memory _listing, Sig memory sig) 
        internal
    {
        /* CHECKS */

        /* Calculate order hash. */
        bytes32 hash = requireValidListing(_listing, sig);

        /* Assert sender is authorized to cancel order. */
        require(msg.sender == _listing.stakeOwner || msg.sender == _listing.seller);
  
        /* EFFECTS */
      
        /* Mark order as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;

        /* Log cancel event. */
        emit ListingCancelled(hash);
    }

    function report(Listing memory _listing, Sig memory sig) public payable returns (bytes32 hash){
        /* CHECKS */
        hash = requireValidListing(_listing, sig);
        require(disputes[hash].status == Status.NoDispute, "Listing has already been reported");
        require(now < _listing.creationTimestamp + reportTimeout, "Report time has expired");
        require(msg.sender != _listing.stakeOwner, "You can't report yourself. Use cancelListing()");
        uint arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(msg.value >= arbitrationCost, "Value must be greater than arbitrationCost");
        Seller storage prosecution = sellers[msg.sender];
        Seller storage defendant = sellers[_listing.stakeOwner];
        uint availableBalance = prosecution.balance - prosecution.lockedTokens;
        if(availableBalance < _listing.stakedAmount) {
            require(marketToken.transferFrom(msg.sender, address(this), _listing.stakedAmount - availableBalance), "Unable to transfer tokens");
            prosecution.balance += _listing.stakedAmount - availableBalance;
        }
        /* EFFECTS */
        prosecution.lockedTokens += _listing.stakedAmount;
        defendant.lockedTokens += _listing.stakedAmount;
        RunningDispute storage dispute = disputes[hash];
        dispute.prosecution = msg.sender;
        dispute.defendant = _listing.stakeOwner;
        dispute.amount = _listing.stakedAmount;
        dispute.token = marketToken;
        dispute.prosecutionFee + msg.value;
        dispute.disputeType = DisputeType.Report;
        dispute.status = Status.WaitingDefendant;
        dispute.lastInteraction = now;
        dispute.metaEvidenceId = metaEvidenceCount++;
        emit MetaEvidence(dispute.metaEvidenceId, string(abi.encodePacked(ipfsDomain, _listing.ipfsHash)));
        emit HasToPayFee(hash, Party.Defendant);
    }

    function disputeTimeOut(bytes32 hash) public {
        RunningDispute storage dispute = disputes[hash];
        require(Status.NoDispute > dispute.status && dispute.status < Status.DisputeCreated, "Dispute is not waiting for any party.");
        require(now - dispute.lastInteraction >= feeTimeout, "Timeout time has not passed yet.");
        if (dispute.prosecutionFee != 0) {
            dispute.prosecution.transfer(dispute.prosecutionFee);
            dispute.prosecutionFee = 0;
        }
        if (dispute.defendantFee != 0) {
            dispute.defendant.transfer(dispute.defendantFee);
            dispute.defendantFee = 0;
        }
        if(dispute.status == Status.WaitingDefendant) {
            executeReportRuling(dispute, uint(RulingOptions.ProsecutionWins));
        } else {
            executeReportRuling(dispute, uint(RulingOptions.DefendantWins));
        }
    }

    function payArbitrationFee(bytes32 hash) public payable {
        RunningDispute storage dispute = disputes[hash];
        uint arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(Status.NoDispute > dispute.status && dispute.status < Status.DisputeCreated, "Dispute has already been created.");
        require(msg.sender == dispute.prosecution || msg.sender == dispute.defendant, "The caller must be the sender.");

        if (msg.sender == dispute.prosecution) {
            dispute.prosecutionFee += msg.value;
            require(dispute.prosecutionFee >= arbitrationCost, "The prosecution fee must cover arbitration costs.");
            dispute.lastInteraction = now;
            if (dispute.defendantFee < arbitrationCost) {
                dispute.status = Status.WaitingDefendant;
                emit HasToPayFee(hash, Party.Defendant);
            } else { // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost, reportExtraData);
            }
        } else {
            dispute.defendantFee += msg.value;
            require(dispute.defendantFee >= arbitrationCost, "The prosecution fee must cover arbitration costs.");
            dispute.lastInteraction = now;
            if (dispute.prosecutionFee < arbitrationCost) {
                dispute.status = Status.WaitingProsecution;
                emit HasToPayFee(hash, Party.Prosecution);
            } else { // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost, reportExtraData);
            }
        }
    }

    function raiseDispute(bytes32 hash, uint _arbitrationCost, bytes memory extraData) internal {
        RunningDispute storage dispute = disputes[hash];
        dispute.status = Status.DisputeCreated;
        uint disputeId = arbitrator.createDispute{value: _arbitrationCost}(AMOUNT_OF_CHOICES, extraData);
        disputeIDtoHash[disputeId] = hash;
        emit Dispute(arbitrator, disputeId, dispute.metaEvidenceId, dispute.metaEvidenceId);

        // Refund sender if it overpaid.
        if (dispute.prosecutionFee > _arbitrationCost) {
            uint extraFeeProsecution = dispute.prosecutionFee - _arbitrationCost;
            dispute.prosecutionFee = _arbitrationCost;
            dispute.prosecution.transfer(extraFeeProsecution);
        }

        // Refund receiver if it overpaid.
        if (dispute.defendantFee > _arbitrationCost) {
            uint extraFeeDefendant = dispute.defendantFee - _arbitrationCost;
            dispute.defendantFee = _arbitrationCost;
            dispute.defendant.transfer(extraFeeDefendant);
        }
    }

    function rule(uint _disputeID, uint _ruling) public override {
        emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);
        bytes32 hash = disputeIDtoHash[_disputeID];
        RunningDispute storage dispute = disputes[hash];
        if (dispute.disputeType == DisputeType.Report) {
            executeReportRuling(dispute, _ruling);
        } else {
            executeOrderRuling(dispute, _ruling);
        }
    }

    function executeOrderRuling(RunningDispute storage dispute, uint _ruling) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint amount = dispute.amount;
        uint prosecutionFee = dispute.prosecutionFee;
        uint defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = Status.Resolved;
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
            (success, ) = dispute.defendant.call{value: defendantFee - splitArbitrationFee}("");
            (success, ) = dispute.prosecution.call{value: splitArbitrationFee}("");
            uint half = amount / 2;
            require(dispute.token.transfer(dispute.defendant, amount - half), "The `transfer` function must not fail.");
            require(dispute.token.transfer(dispute.prosecution, half), "The `transfer` function must not fail.");
        }
    }

    function executeReportRuling(RunningDispute storage dispute, uint _ruling) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint amount = dispute.amount;
        uint prosecutionFee = dispute.prosecutionFee;
        uint defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = Status.Resolved;
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
        /* Listing isn't valid yet. */
        if (now < _listing.creationTimestamp) {
            require(false, "Listing isn't valid yet.");
            return false;
        }
        /* Listing has expiration time */
        if (_listing.expiration != 0) {
            /* Listing creation timestamp is greater than expiration */
            if (_listing.creationTimestamp > _listing.expiration){
                require(false, "Listing creation timestamp is greater than expiration");
                return false;
            }
            /* Listing has expired */
            if (now > _listing.expiration){
                require(false, "Listing has expired");
                return false;
            }
        }

        /* Stake owner must have enough tokens */
        if (sellers[_listing.stakeOwner].balance - sellers[_listing.stakeOwner].lockedTokens < _listing.stakedAmount) {
            require(false, "Stake owner must have enough tokens");
            return false;
        }
        
        /* Listing must have not been canceled or already filled. */
        if (cancelledOrFinalized[hash]) {
            require(false, "Listing must have not been canceled or already filled.");
            return false;
        }

        /* Order authentication. Order must be either:
        /* (a) previously approved */
        if (approvedOrders[hash]) {
            return true;
        }

        /* or (b) ECDSA-signed by maker. */
        if (ecrecover(hash, sig.v, sig.r, sig.s) == _listing.stakeOwner) {
            return true;
        }
        require(false, "Not signed properly.");

        return false;
    }

    function hashListing(Listing memory listing)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(abi.encodePacked(listing.ipfsHash, listing.seller, listing.stakeOwner, listing.stakedAmount, listing.commissionPercentage, listing.creationTimestamp, listing.warrantyTimeout, listing.expiration));
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

    // function bytes32ToString(bytes32 x) constant returns (string) {
    //     bytes memory bytesString = new bytes(32);
    //     uint charCount = 0;
    //     for (uint j = 0; j < 32; j++) {
    //         byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
    //         if (char != 0) {
    //             bytesString[charCount] = char;
    //             charCount++;
    //         }
    //     }
    //     bytes memory bytesStringTrimmed = new bytes(charCount);
    //     for (j = 0; j < charCount; j++) {
    //         bytesStringTrimmed[j] = bytesString[j];
    //     }
    //     return string(bytesStringTrimmed);
    // }
}