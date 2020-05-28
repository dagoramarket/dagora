// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

import "../token/ERC20Burnable.sol";

import "../utils/Ownable.sol";


contract Dagora is IArbitrable, Ownable {
    /* 2 decimal plates for percentage */
    uint256 public constant INVERSE_BASIS_POINT = 10000;

    uint8 constant AMOUNT_OF_CHOICES = 2;

    enum Party {Prosecution, Defendant}
    enum DisputeType {None, Report, Order}
    enum RulingOptions {NoRuling, ProsecutionWins, DefendantWins}
    enum DisputeStatus {
        NoDispute,
        WaitingProsecution,
        WaitingDefendant,
        DisputeCreated,
        Resolved
    }
    enum Status {
        NoTransaction,
        WaitingConfirmation,
        Warranty,
        WarrantyConfirmation,
        InDispute,
        Finalized
    }

    struct Listing {
        bytes32 ipfsHash;
        address payable seller;
        address payable stakeOwner;
        uint256 stakedAmount;
        uint256 commissionPercentage; /* two decimal places */
        uint256 warranty; /* In days */
        uint256 cashbackPercentage; /* two decimal places */
        uint256 expiration;
    }

    struct Order {
        Listing listing;
        address payable fundsHolder;
        address payable buyer;
        address payable commissioner;
        ERC20 token;
        uint256 total;
        uint256 shippingCost;
        uint256 expiration;
        uint256 confirmationTimeout; /* In days */
    }

    struct Transaction {
        /* Keep track of status update */
        uint256 lastStatusUpdate;
        /* Refund the seller can give */
        uint256 refund;
        /* Current status */
        Status status;
    }

    struct Seller {
        // The amount of tokens the contract holds for this seller.
        uint256 balance;
        /* Total number of tokens the seller can loose in disputes they are.
         * Those tokens are locked. Note that we can have lockedTokens > balance but it should
         * be statistically unlikely and does not pose issues.*/
        uint256 lockedTokens;
        uint256 blackListExpire;
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
        uint256 amount;
        ERC20 token;
        uint256 prosecutionFee;
        uint256 defendantFee;
        DisputeType disputeType;
        uint256 lastInteraction;
        uint256 metaEvidenceId;
        uint256 disputeId;
        DisputeStatus status;
    }

    event TokenGranted(address indexed addr);
    event TokenRevoked(address indexed addr);

    event TokenDeposited(address indexed sender, uint256 value);
    event TokenWithdrawed(address indexed sender, uint256 value);

    event ListingApproved(bytes32 indexed hash);
    event ListingCancelled(bytes32 indexed hash);

    event OrderApproved(bytes32 indexed hash);
    event OrderCancelled(bytes32 indexed hash);

    event TransactionCreated(
        bytes32 indexed hash,
        address indexed buyer,
        address indexed seller,
        address stakeOwner,
        address commissioner,
        ERC20 token,
        uint256 total,
        uint256 commissionPercentage,
        uint256 cashbackPercentage,
        uint256 confirmationTimeout
    );

    event TransactionRefunded(bytes32 indexed hash, uint256 value);
    event TransactionFinalized(bytes32 indexed hash);

    event WarrantyClaimed(bytes32 indexed hash);

    event HasToPayFee(bytes32 indexed _hash, Party _party);

    mapping(address => Seller) public sellers;
    /* Cancelled / finalized listings and orders, by hash. */
    mapping(bytes32 => bool) public cancelledOrFinalized;
    /* Orders and listings verified by on-chain approval (alternative to ECDSA
     * signatures so that smart contracts can place orders and listings
     * directly). */
    mapping(bytes32 => bool) public approvedHashes;

    mapping(bytes32 => Transaction) public transactions; // Listing Hash to Dispute

    mapping(bytes32 => RunningDispute) public disputes; // Listing Hash to Dispute
    mapping(uint256 => bytes32) public disputeIDtoHash;

    Arbitrator public arbitrator; // Address of the arbitrator contract.
    bytes public reportExtraData; // Extra data to set up the arbitration.
    bytes public orderExtraData; // Extra data to set up the arbitration.
    uint256 public blackListTimeout;
    uint256 public feeTimeout;
    /* Time in seconds a party can take to pay arbitration
     * fees before being considered unresponding and lose the dispute.*/

    mapping(address => bool) public contracts;

    // mapping(address => mapping(address => uint)) public balances;

    ERC20Burnable public marketToken;
    uint256 public metaEvidenceCount;
    string public ipfsDomain;

    uint256 public protocolFeePercentage;
    uint256 public tokenOwnerFeePercentage;
    address public protocolFeeRecipient;

    constructor(
        address _arbitrator,
        address _token,
        address _protocolFeeRecipient,
        uint256 _feeTimeoutDays,
        uint256 _blacklistTimeoutDays,
        uint256 _protocolFeePercentage,
        uint256 _tokenOwnerFeePercentage,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    ) public Ownable() {
        arbitrator = Arbitrator(_arbitrator);
        marketToken = ERC20Burnable(_token);
        protocolFeeRecipient = _protocolFeeRecipient;
        feeTimeout = _feeTimeoutDays * (1 days);
        blackListTimeout = _blacklistTimeoutDays * (1 days);
        protocolFeePercentage = _protocolFeePercentage;
        tokenOwnerFeePercentage = _tokenOwnerFeePercentage;
        reportExtraData = _reportExtraData;
        orderExtraData = _orderExtraData;
        ipfsDomain = _ipfsDomain;
    }

    function grantAuthentication(address addr) public onlyOwner {
        require(!contracts[addr]);
        contracts[addr] = true;
        emit TokenGranted(addr);
    }

    function revokeAuthentication(address addr) public onlyOwner {
        contracts[addr] = false;
        emit TokenRevoked(addr);
    }

    function depositTokens(uint256 value) public {
        require(marketToken.transferFrom(msg.sender, address(this), value));
        sellers[msg.sender].balance += value;
        emit TokenDeposited(msg.sender, value);
    }

    function withdrawTokens(uint256 value) public {
        Seller storage seller = sellers[msg.sender];
        require(
            seller.balance - seller.lockedTokens >= value,
            "You don't have enoght tokens"
        );
        require(marketToken.transferFrom(msg.sender, address(this), value));
        sellers[msg.sender].balance -= value;
        emit TokenWithdrawed(msg.sender, value);
    }

    function approveListing(Listing memory _listing) public returns (bool) {
        /* CHECKS */
        /* Assert sender is authorized to approve listing. */
        require(
            msg.sender == _listing.stakeOwner,
            "Sender is not listing signer"
        );
        require(
            sellers[msg.sender].balance >= _listing.stakedAmount,
            "You don't have enoght funds"
        );
        /* Calculate listing hash. */
        bytes32 hash = hashListingToSign(_listing);
        /* Assert listing has not already been approved. */
        require(!approvedHashes[hash], "Already approved");
        /* EFFECTS */
        /* Mark listing as approved. */
        approvedHashes[hash] = true;
        emit ListingApproved(hash);
        return true;
    }

    function cancelListing(Listing memory _listing, Sig memory sig) internal {
        /* CHECKS */
        /* Calculate listing hash. */
        bytes32 hash = requireValidListing(_listing, sig);

        /* Assert sender is authorized to cancel listing. */
        require(
            msg.sender == _listing.stakeOwner || msg.sender == _listing.seller
        );

        /* EFFECTS */

        /* Mark listing as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;

        /* Log cancel event. */
        emit ListingCancelled(hash);
    }

    function approveOrder(Order memory order) public returns (bool) {
        /* CHECKS */
        /* Assert sender is authorized to approve listing. */
        require(msg.sender == order.fundsHolder, "Sender is not order signer");
        /* Calculate listing hash. */
        bytes32 hash = hashOrderToSign(order);
        /* Assert listing has not already been approved. */
        require(!approvedHashes[hash], "Already approved");
        /* EFFECTS */
        /* Mark order as approved. */
        approvedHashes[hash] = true;

        emit OrderApproved(hash);
        return true;
    }

    function cancelOrder(Order memory order, Sig memory orderSig, Sig memory listingSig) internal {
        /* CHECKS */

        /* Calculate listing hash. */
        bytes32 hash = requireValidOrder(order, orderSig, listingSig);

        /* Assert sender is authorized to cancel listing. */
        require(msg.sender == order.buyer);

        /* EFFECTS */

        /* Mark listing as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;

        /* Log cancel event. */
        emit OrderCancelled(hash);
    }

    function createTransaction(
        Order memory _order,
        Sig memory orderSig,
        Sig memory listingSig
    ) public returns (bytes32 hash) {
        hash = requireValidOrder(_order, orderSig, listingSig);
        require(
            transactions[hash].status == Status.NoTransaction,
            "Order already has been processed"
        );
        uint256 amount = _order.total + _order.shippingCost;
        require(
            _order.token.transferFrom(_order.fundsHolder, address(this), amount),
            "Failed to transfer buyer's funds."
        );
        transactions[hash].lastStatusUpdate = now;
        transactions[hash].status = Status.WaitingConfirmation;
        emit TransactionCreated(
            hash,
            _order.buyer,
            _order.listing.seller,
            _order.listing.stakeOwner,
            _order.commissioner,
            _order.token,
            amount,
            _order.listing.commissionPercentage,
            _order.listing.cashbackPercentage,
            _order.confirmationTimeout
        );
    }

    function confirmReceipt(Order memory _order)
        public
    {
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(
            (transaction.status == Status.WaitingConfirmation &&
                msg.sender == _order.buyer) ||
                (transaction.status == Status.WarrantyConfirmation &&
                    msg.sender == _order.listing.seller),
            "You must be seller or buyer in the right phase."
        );
        if (transaction.refund == 0 && _order.listing.warranty > 0) {
            transaction.status = Status.Warranty;
            transaction.lastStatusUpdate = now;
        } else {
            uint256 total = SafeMath.add(_order.total, _order.shippingCost);
            finalizeTransaction(
                hash,
                _order.buyer,
                _order.listing.seller,
                _order.commissioner,
                _order.listing.stakeOwner,
                _order.token,
                total,
                transaction.refund,
                _order.listing.commissionPercentage,
                _order.listing.cashbackPercentage
            );
        }
    }

    function executeTransaction(Order memory _order)
        public
    {
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation ||
                transaction.status == Status.Warranty ||
                transaction.status == Status.WarrantyConfirmation,
            "Invalid phase"
        );
        uint256 cashbackPercentage;
        if (
            transaction.status == Status.WaitingConfirmation ||
            transaction.status == Status.WarrantyConfirmation
        ) {
            require(
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)) >
                    now,
                "Timeout time has not passed yet."
            );
            cashbackPercentage = 0;
        } else {
            require(
                transaction.lastStatusUpdate + (_order.listing.warranty * (1 days)) >
                    now,
                "Timeout time has not passed yet."
            );
            cashbackPercentage = _order.listing.cashbackPercentage;
        }
        uint256 total = _order.total + _order.shippingCost;
        finalizeTransaction(
            hash,
            _order.buyer,
            _order.listing.seller,
            _order.commissioner,
            _order.listing.stakeOwner,
            _order.token,
            total,
            transaction.refund,
            _order.listing.commissionPercentage,
            cashbackPercentage
        );
    }

    function finalizeTransaction(
        bytes32 hash,
        address buyer,
        address seller,
        address commissioner,
        address stakeHolder,
        ERC20 token,
        uint256 total,
        uint256 refund,
        uint256 commissionPercentage,
        uint256 cashbackPercentage
    ) internal {
        require(address(token) != address(0));
        require(contracts[address(token)]);

        transactions[hash].status = Status.Finalized;
        delete transactions[hash].lastStatusUpdate;

        uint256 price = SafeMath.sub(total, refund);

        if (protocolFeePercentage > 0) {
            uint256 protocolFee = SafeMath.div(
                SafeMath.mul(protocolFeePercentage, price),
                INVERSE_BASIS_POINT
            );
            price = SafeMath.sub(price, protocolFee);
            require(token.transfer(protocolFeeRecipient, protocolFee));
        }

        if (tokenOwnerFeePercentage > 0 && seller != stakeHolder) {
            uint256 stakeOwnerFee = SafeMath.div(
                SafeMath.mul(tokenOwnerFeePercentage, price),
                INVERSE_BASIS_POINT
            );
            price = SafeMath.sub(price, stakeOwnerFee);
            require(token.transfer(stakeHolder, stakeOwnerFee));
        }

        if (commissionPercentage > 0 && commissioner != address(0x0)) {
            uint256 commissionFee = SafeMath.div(
                SafeMath.mul(commissionPercentage, price),
                INVERSE_BASIS_POINT
            );
            price = SafeMath.sub(price, commissionFee);
            require(token.transfer(commissioner, commissionFee));
        }

        if (cashbackPercentage > 0) {
            uint256 cashback = SafeMath.div(
                SafeMath.mul(cashbackPercentage, price),
                INVERSE_BASIS_POINT
            );
            price = SafeMath.sub(price, cashback);
            require(token.transfer(buyer, cashback + refund));
        }

        if (price > 0){
            require(token.transfer(seller, price));
        }
        emit TransactionFinalized(hash);
    }

    function claimWarranty(Order memory _order)
        public
    {
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(transaction.status == Status.Warranty, "Invalid phase");
        require(msg.sender == _order.buyer, "You must be buyer");
        require(
            now <=
                transaction.lastStatusUpdate + (_order.listing.warranty * (1 days)),
            "Warranty time has timed out."
        );

        transaction.status = Status.WarrantyConfirmation;
        transaction.refund = _order.total;
        transaction.lastStatusUpdate = now;
        emit WarrantyClaimed(hash);
    }

    function disputeTransaction(Order memory _order)
        public
        payable
        returns (bytes32 hash)
    {
        hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation ||
                transaction.status == Status.WarrantyConfirmation,
            "Invalid phase"
        );
        require(
            now <=
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)),
            "Confirmation time has timed out."
        );
        uint256 arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(
            msg.value >= arbitrationCost,
            "Value must be greater than arbitrationCost"
        );
        address payable prosecution;
        address payable defendant;
        if (transaction.status == Status.WaitingConfirmation) {
            require(msg.sender == _order.buyer, "Only buyer can dispute.");
            prosecution = _order.buyer;
            defendant = _order.listing.seller;
        } else {
            require(msg.sender == _order.listing.seller, "Only seller can dispute.");
            prosecution = _order.buyer;
            defendant = _order.listing.seller;
        }
        transaction.status = Status.InDispute;
        transaction.lastStatusUpdate = now;
        RunningDispute storage dispute = _createDispute(
            hash,
            prosecution,
            defendant,
            _order.total,
            _order.token,
            msg.value,
            DisputeType.Order
        );
        emit MetaEvidence(
            dispute.metaEvidenceId,
            string(abi.encodePacked(ipfsDomain, _order.listing.ipfsHash))
        );
    }

    function updateRefund(
        Order memory _order,
        uint256 refund
    ) public {
        require(
            msg.sender == _order.listing.seller,
            "You must be the listing seller"
        );
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation,
            "Invalid phase"
        );
        require(
            now <=
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)),
            "Confirmation time has timed out."
        );
        require(refund <= _order.total, "Refund can't be greater than total.");
        transaction.refund = refund;
        emit TransactionRefunded(hash, refund);
    }

    function report(Listing memory _listing, Sig memory sig)
        public
        payable
        returns (bytes32 hash)
    {
        /* CHECKS */
        hash = requireValidListing(_listing, sig);
        require(
            disputes[hash].status == DisputeStatus.NoDispute,
            "Listing has already been reported"
        );
        require(
            msg.sender != _listing.stakeOwner,
            "You can't report yourself. Use cancelListing()"
        );
        uint256 arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(
            msg.value >= arbitrationCost,
            "Value must be greater than arbitrationCost"
        );
        Seller storage prosecution = sellers[msg.sender];
        require(
            now > prosecution.blackListExpire,
            "You are not allowed to report listings."
        );
        uint256 availableBalance = prosecution.balance -
            prosecution.lockedTokens;
        if (availableBalance < _listing.stakedAmount) {
            require(
                marketToken.transferFrom(
                    msg.sender,
                    address(this),
                    _listing.stakedAmount - availableBalance
                ),
                "Unable to transfer tokens"
            );
            prosecution.balance += _listing.stakedAmount - availableBalance;
        }
        /* EFFECTS */

        Seller storage defendant = sellers[_listing.stakeOwner];
        prosecution.lockedTokens += _listing.stakedAmount;
        defendant.lockedTokens += _listing.stakedAmount;
        RunningDispute storage dispute = _createDispute(
            hash,
            msg.sender,
            _listing.stakeOwner,
            _listing.stakedAmount,
            marketToken,
            msg.value,
            DisputeType.Report
        );
        emit MetaEvidence(
            dispute.metaEvidenceId,
            string(abi.encodePacked(ipfsDomain, _listing.ipfsHash))
        );
    }

    function _createDispute(
        bytes32 hash,
        address payable prosecution,
        address payable defendant,
        uint256 amount,
        ERC20 token,
        uint256 prosecutionFee,
        DisputeType disputeType
    ) internal returns (RunningDispute storage dispute) {
        dispute = disputes[hash];
        dispute.prosecution = prosecution;
        dispute.defendant = defendant;
        dispute.amount = amount;
        dispute.prosecutionFee += prosecutionFee;
        dispute.disputeType = disputeType;
        /* We know the token is market token, save gas*/
        if (disputeType == DisputeType.Report) dispute.token = token;
        dispute.status = DisputeStatus.WaitingDefendant;
        dispute.lastInteraction = now;
        dispute.metaEvidenceId = metaEvidenceCount++;
        emit HasToPayFee(hash, Party.Defendant);
    }

    function disputeTimeout(bytes32 hash) public {
        RunningDispute storage dispute = disputes[hash];
        require(
            DisputeStatus.NoDispute < dispute.status &&
                dispute.status < DisputeStatus.DisputeCreated,
            "Dispute is not waiting for any party."
        );
        require(
            now - dispute.lastInteraction >= feeTimeout,
            "Timeout time has not passed yet."
        );
        bool success;
        if (dispute.prosecutionFee != 0) {
            uint256 prosecutionFee = dispute.prosecutionFee;
            dispute.prosecutionFee = 0;
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
        }
        if (dispute.defendantFee != 0) {
            uint256 defendantFee = dispute.defendantFee;
            dispute.defendantFee = 0;
            (success, ) = dispute.defendant.call{value: defendantFee}("");
        }
        if (dispute.status == DisputeStatus.WaitingDefendant) {
            executeReportRuling(
                dispute,
                uint256(RulingOptions.ProsecutionWins)
            );
        } else {
            executeReportRuling(dispute, uint256(RulingOptions.DefendantWins));
        }
    }

    function payArbitrationFee(bytes32 hash) public payable {
        RunningDispute storage dispute = disputes[hash];
        uint256 arbitrationCost = arbitrator.arbitrationCost(reportExtraData);
        require(
            DisputeStatus.NoDispute < dispute.status &&
                dispute.status < DisputeStatus.DisputeCreated,
            "Dispute has already been created."
        );
        require(
            msg.sender == dispute.prosecution ||
                msg.sender == dispute.defendant,
            "The caller must be the sender."
        );

        if (msg.sender == dispute.prosecution) {
            dispute.prosecutionFee += msg.value;
            require(
                dispute.prosecutionFee >= arbitrationCost,
                "The prosecution fee must cover arbitration costs."
            );
            dispute.lastInteraction = now;
            if (dispute.defendantFee < arbitrationCost) {
                dispute.status = DisputeStatus.WaitingDefendant;
                emit HasToPayFee(hash, Party.Defendant);
            } else {
                // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost);
            }
        } else {
            dispute.defendantFee += msg.value;
            require(
                dispute.defendantFee >= arbitrationCost,
                "The prosecution fee must cover arbitration costs."
            );
            dispute.lastInteraction = now;
            if (dispute.prosecutionFee < arbitrationCost) {
                dispute.status = DisputeStatus.WaitingProsecution;
                emit HasToPayFee(hash, Party.Prosecution);
            } else {
                // The receiver has also paid the fee. We create the dispute.
                raiseDispute(hash, arbitrationCost);
            }
        }
    }

    function raiseDispute(bytes32 hash, uint256 _arbitrationCost) internal {
        RunningDispute storage dispute = disputes[hash];
        dispute.status = DisputeStatus.DisputeCreated;
        uint256 disputeId = arbitrator.createDispute{value: _arbitrationCost}(
            AMOUNT_OF_CHOICES,
            dispute.disputeType == DisputeType.Order
                ? orderExtraData
                : reportExtraData
        );
        disputeIDtoHash[disputeId] = hash;
        emit Dispute(
            arbitrator,
            disputeId,
            dispute.metaEvidenceId,
            dispute.metaEvidenceId
        );
        // Refund sender if it overpaid.
        bool success;
        if (dispute.prosecutionFee > _arbitrationCost) {
            uint256 extraFeeProsecution = dispute.prosecutionFee -
                _arbitrationCost;
            dispute.prosecutionFee = _arbitrationCost;
            (success, ) = dispute.prosecution.call{value: extraFeeProsecution}(
                ""
            );
        }

        // Refund receiver if it overpaid.
        if (dispute.defendantFee > _arbitrationCost) {
            uint256 extraFeeDefendant = dispute.defendantFee - _arbitrationCost;
            dispute.defendantFee = _arbitrationCost;
            (success, ) = dispute.defendant.call{value: extraFeeDefendant}("");
        }
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _hash The hash of the order.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _hash, string memory _evidence) public {
        RunningDispute storage dispute = disputes[_hash];
        require(
            msg.sender == dispute.prosecution ||
                msg.sender == dispute.defendant,
            "The caller must be the prosecution or the defendant."
        );
        require(
            dispute.disputeType == DisputeType.Order,
            "Evidences are only allowed for orders disputes."
        );
        require(
            dispute.status < DisputeStatus.Resolved,
            "Must not send evidence if the dispute is resolved."
        );

        emit Evidence(
            arbitrator,
            dispute.metaEvidenceId,
            msg.sender,
            _evidence
        );
    }

    /** @dev Appeal an appealable ruling. UNTRUSTED.
     *  Transfer the funds to the arbitrator.
     *  Note that no checks are required as the checks are done by the arbitrator.
     *  @param _hash The hash of the order.
     */
    function appeal(bytes32 _hash) public payable {
        RunningDispute storage dispute = disputes[_hash];
        require(
            dispute.disputeType == DisputeType.Order,
            "Appeals are only allowed for orders disputes."
        );

        arbitrator.appeal{value: msg.value}(dispute.disputeId, orderExtraData);
    }

    function rule(uint256 _disputeID, uint256 _ruling) public override {
        bytes32 hash = disputeIDtoHash[_disputeID];
        RunningDispute storage dispute = disputes[hash];
        require(
            msg.sender == address(arbitrator),
            "The caller must be the arbitrator."
        );
        require(
            dispute.status == DisputeStatus.DisputeCreated,
            "The dispute has already been resolved."
        );
        emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);
        if (dispute.disputeType == DisputeType.Report) {
            executeReportRuling(dispute, _ruling);
        } else {
            _executeOrderRuling(dispute, _ruling);
            transactions[hash].status = Status.Finalized;
        }
    }

    function _executeOrderRuling(
        RunningDispute storage dispute,
        uint256 _ruling
    ) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint256 amount = dispute.amount;
        uint256 prosecutionFee = dispute.prosecutionFee;
        uint256 defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = DisputeStatus.Resolved;
        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint256(RulingOptions.ProsecutionWins)) {
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
            require(
                dispute.token.transfer(dispute.prosecution, amount),
                "The `transfer` function must not fail."
            );
        } else if (_ruling == uint256(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{value: defendantFee}("");
            require(
                dispute.token.transfer(dispute.defendant, amount),
                "The `transfer` function must not fail."
            );
        } else {
            // `senderFee` and `receiverFee` are equal to the arbitration cost.
            uint256 splitArbitrationFee = prosecutionFee / 2;
            /* Give 1 wei more to defendant in case of even number */
            (success, ) = dispute.defendant.call{
                value: defendantFee - splitArbitrationFee
            }("");
            (success, ) = dispute.prosecution.call{value: splitArbitrationFee}(
                ""
            );
            uint256 half = amount / 2;
            require(
                dispute.token.transfer(dispute.defendant, amount - half),
                "The `transfer` function must not fail."
            );
            require(
                dispute.token.transfer(dispute.prosecution, half),
                "The `transfer` function must not fail."
            );
        }
    }

    function executeReportRuling(
        RunningDispute storage dispute,
        uint256 _ruling
    ) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        uint256 amount = dispute.amount;
        uint256 prosecutionFee = dispute.prosecutionFee;
        uint256 defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = DisputeStatus.Resolved;
        sellers[dispute.prosecution].lockedTokens -= dispute.amount;
        sellers[dispute.defendant].lockedTokens -= dispute.amount;
        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint256(RulingOptions.ProsecutionWins)) {
            (success, ) = dispute.prosecution.call{value: prosecutionFee}("");
            sellers[dispute.defendant].balance -= amount;
            sellers[dispute.prosecution].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else if (_ruling == uint256(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{value: defendantFee}("");
            sellers[dispute.prosecution].blackListExpire =
                now +
                blackListTimeout;
            sellers[dispute.prosecution].balance -= amount;
            sellers[dispute.defendant].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else {
            // `senderFee` and `receiverFee` are equal to the arbitration cost.
            uint256 splitArbitrationFee = prosecutionFee / 2;
            (success, ) = dispute.defendant.call{
                value: defendantFee - splitArbitrationFee
            }("");
            (success, ) = dispute.prosecution.call{value: splitArbitrationFee}(
                ""
            );
            // In the case of an uneven token amount, one basic token unit can be burnt.
            sellers[dispute.prosecution].balance -= amount / 2;
            sellers[dispute.defendant].balance -= amount / 2;
        }
    }

    function validateListing(
        bytes32 hash,
        Listing memory _listing,
        Sig memory sig
    ) internal view returns (bool) {
        /* Listing has expired */
        if (_listing.expiration != 0 && now > _listing.expiration) {
            return false;
        }

        /* Stake owner must have enough tokens */
        Seller storage stakeOwner = sellers[_listing.stakeOwner];
        if (
            stakeOwner.balance - stakeOwner.lockedTokens < _listing.stakedAmount
        ) {
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

    function validateOrder(
        bytes32 hash,
        Order memory order,
        Sig memory sig
    ) internal view returns (bool) {
        /* Order has expired */
        if (order.expiration != 0 && now > order.expiration) {
            return false;
        }

        /* Token contract must be allowed */
        if (!contracts[address(order.token)]) {
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (cancelledOrFinalized[hash]) {
            return false;
        }

        /* Order authentication. Order must be either:
        /* (a) previously approved */
        if (approvedHashes[hash]) {
            return true;
        }

        /* or (b) ECDSA-signed by buyer. */
        if (ecrecover(hash, sig.v, sig.r, sig.s) == order.buyer) {
            return true;
        }

        return false;
    }

    function hashListing(Listing memory listing)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(
            abi.encodePacked(
                listing.ipfsHash,
                listing.seller,
                listing.stakeOwner,
                listing.stakedAmount,
                listing.commissionPercentage,
                listing.warranty,
                listing.cashbackPercentage,
                listing.expiration
            )
        );
        return hash;
    }

    function hashOrder(Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(
            abi.encodePacked(
                hashListingToSign(order.listing),
                order.buyer,
                order.fundsHolder,
                order.commissioner,
                order.token,
                order.total,
                order.shippingCost,
                order.expiration,
                order.confirmationTimeout
            )
        );
        return hash;
    }

    function hashToSign(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    function hashListingToSign(Listing memory listing)
        internal
        pure
        returns (bytes32)
    {
        return hashToSign(hashListing(listing));
    }

    function hashOrderToSign(Order memory order)
        internal
        pure
        returns (bytes32)
    {
        return hashToSign(hashOrder(order));
    }

    function requireValidListing(Listing memory listing, Sig memory sig)
        internal
        view
        returns (bytes32 hash)
    {
        require(validateListing(hash = hashListingToSign(listing), listing, sig), "Invalid listing");
    }

    function requireValidOrder(Order memory order, Sig memory orderSig, Sig memory listingSig)
        internal
        view
        returns (bytes32 hash)
    {
        require(validateListing(hashListingToSign(order.listing), order.listing, listingSig), "Invalid listing");
        require(validateOrder(hash = hashOrderToSign(order), order, orderSig), "Invalid order");
    }
}
