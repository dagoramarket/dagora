// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Dagora is Ownable {
    /* 2 decimal plates for percentage */
    uint256 public constant INVERSE_BASIS_POINT = 10000;

    uint8 constant AMOUNT_OF_CHOICES = 2;

    enum Party { Prosecution, Defendant }
    enum DisputeType { None, Report, Order }
    enum RulingOptions { NoRuling, ProsecutionWins, DefendantWins }

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
        uint256 cashback;
        uint256 commission;
        uint256 protocolFee;
        uint256 stakeHolderFee;
        uint256 expiration;
        uint256 confirmationTimeout; /* In days */
        uint256 timestamp; /* A buyer may want to buy the same product twice */
    }

    struct Transaction {
        /* Keep track of status update */
        uint256 lastStatusUpdate;
        /* Refund the seller can give */
        uint256 refund;
        /* Refund the seller can give */
        uint256 gasFee;
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
        address _token,
        address _protocolFeeRecipient,
        uint256 _feeTimeoutDays,
        uint256 _blacklistTimeoutDays,
        uint256 _protocolFeePercentage,
        uint256 _tokenOwnerFeePercentage,
        string memory _ipfsDomain
    ) public Ownable() {
        marketToken = ERC20Burnable(_token);
        protocolFeeRecipient = _protocolFeeRecipient;
        feeTimeout = _feeTimeoutDays * (1 days);
        blackListTimeout = _blacklistTimeoutDays * (1 days);
        protocolFeePercentage = _protocolFeePercentage;
        tokenOwnerFeePercentage = _tokenOwnerFeePercentage;
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
        require(marketToken.transferFrom(_msgSender(), address(this), value));
        sellers[_msgSender()].balance += value;
        emit TokenDeposited(_msgSender(), value);
    }

    function withdrawTokens(uint256 value) public {
        Seller storage seller = sellers[_msgSender()];
        require(
            seller.balance - seller.lockedTokens >= value,
            "You don't have enoght tokens"
        );
        require(marketToken.transferFrom(_msgSender(), address(this), value));
        sellers[_msgSender()].balance -= value;
        emit TokenWithdrawed(_msgSender(), value);
    }

    function approveListing(Listing memory _listing) public returns (bool) {
        /* CHECKS */
        /* Assert sender is authorized to approve listing. */
        require(
            _msgSender() == _listing.stakeOwner,
            "Sender is not listing signer"
        );
        require(
            sellers[_msgSender()].balance >= _listing.stakedAmount,
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
            _msgSender() == _listing.stakeOwner ||
                _msgSender() == _listing.seller
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
        require(
            _msgSender() == order.fundsHolder,
            "Sender is not order signer"
        );
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

    function cancelOrder(
        Order memory order,
        Sig memory orderSig,
        Sig memory listingSig
    ) internal {
        /* CHECKS */

        /* Calculate listing hash. */
        bytes32 hash = requireValidOrder(order, orderSig, listingSig);

        /* Assert sender is authorized to cancel listing. */
        require(_msgSender() == order.buyer);

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
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.NoTransaction,
            "Order already has been processed"
        );
        require(
            _order.token.transferFrom(
                _order.fundsHolder,
                address(this),
                _order.total
            ),
            "Failed to transfer buyer's funds."
        );
        transaction.lastStatusUpdate = now;
        transaction.status = Status.WaitingConfirmation;
        emit TransactionCreated(
            hash,
            _order.buyer,
            _order.listing.seller,
            _order.listing.stakeOwner,
            _order.commissioner,
            _order.token,
            _order.total,
            _order.commission,
            _order.cashback,
            _order.confirmationTimeout
        );
    }

    function batchCreateTransaction(
        Order[] memory orders,
        Sig[] memory orderSignatures,
        Sig[] memory listingSignatures
    ) public returns (bytes32[] memory hashes) {
        require(
            orders.length == orderSignatures.length &&
                orderSignatures.length == listingSignatures.length
        );
        hashes = new bytes32[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            hashes[i] = createTransaction(
                orders[i],
                orderSignatures[i],
                listingSignatures[i]
            );
        }
    }

    function confirmReceipt(Order memory _order) public {
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(
            (transaction.status == Status.WaitingConfirmation &&
                _msgSender() == _order.buyer) ||
                (transaction.status == Status.WarrantyConfirmation &&
                    _msgSender() == _order.listing.seller),
            "You must be seller or buyer in the right phase."
        );
        if (transaction.refund == 0 && _order.listing.warranty > 0) {
            transaction.status = Status.Warranty;
            transaction.lastStatusUpdate = now;
        } else {
            finalizeTransaction(_order);
        }
    }

    function executeTransaction(Order memory _order) public {
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
                now >=
                    transaction.lastStatusUpdate +
                        (_order.confirmationTimeout * (1 days)),
                "Timeout time has not passed yet."
            );
            cashbackPercentage = 0;
        } else {
            require(
                now >=
                    transaction.lastStatusUpdate +
                        (_order.listing.warranty * (1 days)),
                "Timeout time has not passed yet."
            );
            cashbackPercentage = _order.listing.cashbackPercentage;
        }
        finalizeTransaction(_order);
    }

    function batchExecuteTransaction(Order[] memory orders) public {
        for (uint256 i = 0; i < orders.length; i++) {
            executeTransaction(orders[i]);
        }
    }

    function finalizeTransaction(Order memory order) internal {
        bytes32 hash = hashOrderToSign(order);
        Transaction storage transaction = transactions[hash];
        uint256 refund = transaction.refund;
        uint256 price = SafeMath.sub(order.total, refund);

        transaction.status = Status.Finalized;
        delete transaction.lastStatusUpdate;
        delete transaction.refund;

        if (order.protocolFee > 0) {
            price -= order.protocolFee;
            require(
                order.token.transfer(protocolFeeRecipient, order.protocolFee)
            );
        }

        if (order.stakeHolderFee > 0) {
            price = SafeMath.sub(price, order.stakeHolderFee);
            require(
                order.token.transfer(
                    order.listing.stakeOwner,
                    order.stakeHolderFee
                )
            );
        }

        if (order.commission > 0) {
            price -= order.commission;
            require(order.token.transfer(order.commissioner, order.commission));
        }

        if (order.cashback > 0) {
            price -= order.cashback;
            require(
                order.token.transfer(order.buyer, (order.cashback + refund))
            );
        }

        if (price > 0) {
            require(order.token.transfer(order.listing.seller, price));
        }
        emit TransactionFinalized(hash);
    }

    function claimWarranty(Order memory _order) public {
        bytes32 hash = hashOrderToSign(_order);
        Transaction storage transaction = transactions[hash];
        require(transaction.status == Status.Warranty, "Invalid phase");
        require(_msgSender() == _order.buyer, "You must be buyer");
        require(
            now <=
                transaction.lastStatusUpdate +
                    (_order.listing.warranty * (1 days)),
            "Warranty time has timed out."
        );

        transaction.status = Status.WarrantyConfirmation;
        transaction.refund = _order.total;
        transaction.lastStatusUpdate = now;
        emit WarrantyClaimed(hash);
    }

    function updateRefund(Order memory _order, uint256 refund) public {
        require(
            _msgSender() == _order.listing.seller,
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
        require(
            refund +
                (_order.cashback +
                    _order.protocolFee +
                    _order.stakeHolderFee +
                    _order.commission) <=
                _order.total,
            "Refund can't be greater than total allowed."
        );
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
            _msgSender() != _listing.stakeOwner,
            "You can't report yourself. Use cancelListing()"
        );
        uint256 arbitrationCost = arbitrationCost(DisputeType.Report);
        require(
            msg.value >= arbitrationCost,
            "Value must be greater than arbitrationCost"
        );
        Seller storage prosecution = sellers[_msgSender()];
        require(
            now > prosecution.blackListExpire,
            "You are not allowed to report listings."
        );
        uint256 availableBalance = prosecution.balance -
            prosecution.lockedTokens;
        if (availableBalance < _listing.stakedAmount) {
            require(
                marketToken.transferFrom(
                    _msgSender(),
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
        _createDispute(
            hash,
            _msgSender(),
            _listing.stakeOwner,
            _listing.stakedAmount,
            marketToken,
            msg.value,
            DisputeType.Report
        );
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
        uint256 arbitrationCost = arbitrationCost(DisputeType.Order);
        require(
            msg.value >= arbitrationCost,
            "Value must be greater than arbitrationCost"
        );
        address payable prosecution;
        address payable defendant;
        if (transaction.status == Status.WaitingConfirmation) {
            require(_msgSender() == _order.buyer, "Only buyer can dispute.");
            prosecution = _order.buyer;
            defendant = _order.listing.seller;
        } else {
            require(
                _msgSender() == _order.listing.seller,
                "Only seller can dispute."
            );
            prosecution = _order.buyer;
            defendant = _order.listing.seller;
        }
        transaction.status = Status.InDispute;
        transaction.lastStatusUpdate = now;
        _createDispute(
            hash,
            prosecution,
            defendant,
            _order.total,
            _order.token,
            msg.value,
            DisputeType.Order
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
            (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
        }
        if (dispute.defendantFee != 0) {
            uint256 defendantFee = dispute.defendantFee;
            dispute.defendantFee = 0;
            (success, ) = dispute.defendant.call{ value: defendantFee }("");
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
        uint256 arbitrationCost = arbitrationCost(dispute.disputeType);
        require(
            DisputeStatus.NoDispute < dispute.status &&
                dispute.status < DisputeStatus.DisputeCreated,
            "Dispute has already been created."
        );
        require(
            _msgSender() == dispute.prosecution ||
                _msgSender() == dispute.defendant,
            "The caller must be the sender."
        );

        if (_msgSender() == dispute.prosecution) {
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

    function raiseDispute(bytes32 hash, uint256 _arbitrationCost)
        internal
        virtual;

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _hash The hash of the order.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _hash, string memory _evidence)
        public
        virtual;

    /** @dev Appeal an appealable ruling. UNTRUSTED.
     *  Transfer the funds to the arbitrator.
     *  Note that no checks are required as the checks are done by the arbitrator.
     *  @param _hash The hash of the order.
     */
    function appeal(bytes32 _hash) public virtual payable;

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
            (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
            require(
                dispute.token.transfer(dispute.prosecution, amount),
                "The `transfer` function must not fail."
            );
        } else if (_ruling == uint256(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{ value: defendantFee }("");
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
            (success, ) = dispute.prosecution.call{
                value: splitArbitrationFee
            }("");
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

    function arbitrationCost(DisputeType _type)
        public
        virtual
        view
        returns (uint256 fee);

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
            (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
            sellers[dispute.defendant].balance -= amount;
            sellers[dispute.prosecution].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else if (_ruling == uint256(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{ value: defendantFee }("");
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
            (success, ) = dispute.prosecution.call{
                value: splitArbitrationFee
            }("");
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

        /* Commission not enough */
        if (
            order.commission <
            calculateTotalFromPercentage(
                order.total,
                order.listing.commissionPercentage
            )
        ) {
            return false;
        }

        /* Cashback not enough */
        if (
            order.cashback <
            calculateTotalFromPercentage(
                order.total,
                order.listing.cashbackPercentage
            )
        ) {
            return false;
        }

        /* Cashback not enough */
        if (
            order.protocolFee <
            calculateTotalFromPercentage(order.total, protocolFeePercentage)
        ) {
            return false;
        }

        /* Stake holder fee not enough */
        if (
            order.listing.stakeOwner != order.listing.seller &&
            order.stakeHolderFee <
            calculateTotalFromPercentage(order.total, tokenOwnerFeePercentage)
        ) {
            return false;
        }

        /* Now enough money for paying taxes */
        if (
            order.total <
            (order.cashback +
                order.protocolFee +
                order.stakeHolderFee +
                order.commission)
        ) {
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
                order.cashback,
                order.commission,
                order.protocolFee,
                order.stakeHolderFee,
                order.expiration,
                order.confirmationTimeout,
                order.timestamp
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
        require(
            validateListing(hash = hashListingToSign(listing), listing, sig),
            "Invalid listing"
        );
    }

    function requireValidOrder(
        Order memory order,
        Sig memory orderSig,
        Sig memory listingSig
    ) internal view returns (bytes32 hash) {
        require(
            validateListing(
                hashListingToSign(order.listing),
                order.listing,
                listingSig
            ),
            "Invalid listing"
        );
        require(
            validateOrder(hash = hashOrderToSign(order), order, orderSig),
            "Invalid order"
        );
    }

    function calculateTotalFromPercentage(uint256 total, uint256 percentage)
        internal
        pure
        returns (uint256)
    {
        return (total * percentage) / INVERSE_BASIS_POINT;
    }

    function chargeGasFee(Order calldata _order, uint256 fee) external {
        Transaction storage transaction = transactions[hashOrderToSign(_order)];
        require(
            transaction.status > Status.NoTransaction &&
                transaction.status < Status.Finalized
        );
        require(availableToken(_order) >= fee);
        transaction.gasFee += fee;
        _order.token.transfer(_msgSender(), fee); // TODO create a cheapier way
    }

    function availableToken(Order memory _order) public view returns (uint256) {
        Transaction storage transaction = transactions[hashOrderToSign(_order)];
        return
            _order.total -
            (transaction.refund +
                transaction.gasFee +
                _order.cashback +
                _order.protocolFee +
                _order.stakeHolderFee +
                _order.commission);
    }
}
