// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
        WaitingSeller,
        WaitingConfirmation,
        Warranty,
        WarrantyConfirmation,
        InDispute,
        Finalized
    }

    struct Listing {
        bytes32 ipfsHash;
        address payable seller;
        uint256 commissionPercentage; /* two decimal places */
        uint256 warranty; /* In days */
        uint256 cashbackPercentage; /* two decimal places */
        uint256 expiration;
    }

    struct Order {
        Listing listing;
        address payable buyer;
        address payable commissioner;
        ERC20 token;
        uint256 quantity;
        uint256 total;
        uint256 cashback;
        uint256 commission;
        uint256 protocolFee;
        uint256 confirmationTimeout; /* In days */
        uint256 nonce; /* A buyer may want to buy the same product twice */
    }

    struct Transaction {
        /* Keep track of status update */
        uint256 lastStatusUpdate;
        /* Refund the seller can give */
        uint256 refund;
        /* Used for GSN transactions */
        uint256 gasFee;
        /* Current status */
        Status status;
    }

    struct ListingInfo {
        /* Products available */
        uint256 available;
        /* Expiration for non-answered transactions */
        uint256 expiration;
        /* Expiration for non-answered transactions */
        uint256 orders;
    }

    struct Staker {
        // The amount of tokens the contract holds for this staker.
        uint256 balance;
        /* Total number of tokens the staker can loose in disputes they are.
         * Those tokens are locked. Note that we can have lockedTokens > balance but it should
         * be statistically unlikely and does not pose issues.*/
        uint256 lockedTokens;
        uint256 blackListExpire;
        uint256 productCount;
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
        bytes32 extraHash;
        DisputeStatus status;
    }

    event UptadeSellerConfirmationTimeout(uint256 when);
    event UptadeBlacklistTimeout(uint256 when);
    event UptadeDisputeTimeout(uint256 when);
    event UptadeMinimumStake(uint256 quantity);
    event UptadeProtocolFeePercentage(uint256 percentage);

    event TokenGranted(address indexed addr);
    event TokenRevoked(address indexed addr);

    event TokenDeposited(address indexed sender, uint256 value);
    event TokenWithdrawed(address indexed sender, uint256 value);

    event ListingUpdated(
        bytes32 indexed hash,
        address indexed seller,
        bytes32 ipfs,
        uint256 expiration,
        uint256 quantity
    );
    event ListingCancelled(bytes32 indexed hash);

    event TransactionCreated(
        bytes32 indexed orderHash,
        bytes32 indexed listingHash,
        address indexed buyer,
        address commissioner,
        ERC20 token,
        uint256 total,
        uint256 commission,
        uint256 cashback,
        uint256 confirmationTimeout
    );

    event TransactionAccepted(bytes32 indexed hash);
    event TransactionCancelled(bytes32 indexed hash);
    event TransactionRefunded(bytes32 indexed hash, uint256 value);
    event TransactionFinalized(bytes32 indexed hash);

    event WarrantyClaimed(bytes32 indexed hash);

    event HasToPayFee(bytes32 indexed _hash, Party _party);

    mapping(address => Staker) public stakers;
    /* Cancelled / finalized listings and orders, by hash. */
    mapping(bytes32 => bool) public cancelledOrFinalized;

    /* Listings running in the contract */
    mapping(bytes32 => ListingInfo) public listingInfos;
    /* Order approve */
    mapping(bytes32 => bool) public orderApprove;
    /* Transactions running in the contract */
    mapping(bytes32 => Transaction) public transactions; // Order Hash to Transaction
    /* Disputes running in the contract*/
    mapping(bytes32 => RunningDispute) public disputes; // Listing/Order Hash to Dispute

    /* Tokens allowed */
    mapping(address => bool) public contracts;

    ERC20Burnable public marketToken;
    uint256 public metaEvidenceCount;

    /**
        Protocol fee paramenters
     */
    uint256 public PROTOCOL_FEE_PERCENTAGE;
    address public protocolFeeRecipient;

    /* Black listed*/
    uint256 public BLACKLIST_TIMEOUT;
    uint256 public DISPUTE_TIMEOUT;
    uint256 public SELLER_CONFIRMATION_TIMEOUT;

    uint256 public MINIMUM_STAKED_TOKEN;
    uint256 public PERCENTAGE_BURN;
    uint256 public GRACE_PERIOD;

    constructor(address _token, address _protocolFeeRecipient) Ownable() {
        marketToken = ERC20Burnable(_token);
        protocolFeeRecipient = _protocolFeeRecipient;
        PROTOCOL_FEE_PERCENTAGE = 100; // Default 1%
        SELLER_CONFIRMATION_TIMEOUT = 7 * (1 days); // Default = 7 days
    }

    function updateProtocolFeePercentage(uint256 _percent) public onlyOwner {
        PROTOCOL_FEE_PERCENTAGE = _percent;
        emit UptadeProtocolFeePercentage(PROTOCOL_FEE_PERCENTAGE);
    }

    function updateSellerConfirmationTimeout(
        uint256 _sellerConfirmationTimeoutDays
    ) public onlyOwner {
        SELLER_CONFIRMATION_TIMEOUT = _sellerConfirmationTimeoutDays * (1 days);
        emit UptadeSellerConfirmationTimeout(SELLER_CONFIRMATION_TIMEOUT);
    }

    function updateBlacklistTimeout(uint256 _blacklistTimeoutDays)
        public
        onlyOwner
    {
        BLACKLIST_TIMEOUT = _blacklistTimeoutDays * (1 days);
        emit UptadeBlacklistTimeout(BLACKLIST_TIMEOUT);
    }

    function updateDisputeTimeout(uint256 _feeTimeoutDays) public onlyOwner {
        DISPUTE_TIMEOUT = _feeTimeoutDays * (1 days);
        emit UptadeDisputeTimeout(DISPUTE_TIMEOUT);
    }

    function updateMinimumStakeToken(uint256 _quantity) public onlyOwner {
        MINIMUM_STAKED_TOKEN = _quantity;
        emit UptadeMinimumStake(_quantity);
    }

    function grantAuthentication(address _addr) public onlyOwner {
        require(!contracts[_addr]);
        contracts[_addr] = true;
        emit TokenGranted(_addr);
    }

    function revokeAuthentication(address _addr) public onlyOwner {
        contracts[_addr] = false;
        emit TokenRevoked(_addr);
    }

    function stakeTokens(uint256 _value) public {
        require(marketToken.transferFrom(_msgSender(), address(this), _value));
        stakers[_msgSender()].balance += _value;
        emit TokenDeposited(_msgSender(), _value);
    }

    function unstakeTokens(uint256 _value) public {
        Staker storage staker = stakers[_msgSender()];
        require(
            staker.balance - staker.lockedTokens >= _value,
            "You don't have enoght tokens"
        );
        if (staker.productCount > 0) {
            require(
                staker.lockedTokens - MINIMUM_STAKED_TOKEN >= _value,
                "You don't have enoght tokens"
            );
        }
        require(marketToken.transferFrom(_msgSender(), address(this), _value));
        stakers[_msgSender()].balance -= _value;
        emit TokenWithdrawed(_msgSender(), _value);
    }

    function updateListing(Listing memory _listing, uint256 _quantity)
        public
        returns (bool)
    {
        /* CHECKS */
        /* Assert sender is authorized to approve listing. */
        require(_msgSender() == _listing.seller, "You must be the seller");

        /* Calculate listing hash. */
        bytes32 hash = _requireValidListing(_listing);

        if (
            listingInfos[hash].expiration < block.timestamp &&
            listingInfos[hash].orders > 0
        ) {
            // BURN TOKENS
            _burnStake(_msgSender());
        }
        require(
            stakers[_msgSender()].balance >= MINIMUM_STAKED_TOKEN,
            "You don't have enoght funds"
        );

        /* Assert listing has not already been approved. */
        /* EFFECTS */
        uint256 stakerCount =
            SafeMath.add(
                SafeMath.sub(
                    stakers[_msgSender()].productCount,
                    listingInfos[hash].available
                ),
                _quantity
            );

        listingInfos[hash].available = _quantity;
        listingInfos[hash].expiration = _listing.expiration;

        stakers[_msgSender()].productCount = stakerCount;

        emit ListingUpdated(
            hash,
            _listing.seller,
            _listing.ipfsHash,
            _listing.expiration,
            _quantity
        );
        return true;
    }

    function cancelListing(Listing memory _listing) public {
        /* CHECKS */
        /* Calculate listing hash. */
        bytes32 hash = _requireValidListing(_listing);

        /* Assert sender is authorized to cancel listing. */
        require(_msgSender() == _listing.seller, "You must be the seller");
        /* EFFECTS */

        if (
            listingInfos[hash].expiration < block.timestamp &&
            listingInfos[hash].orders > 0
        ) {
            // BURN TOKENS
            _burnStake(_msgSender());
        }

        /* Mark listing as cancelled, preventing it from being matched. */
        cancelledOrFinalized[hash] = true;
        stakers[_msgSender()].productCount = SafeMath.sub(
            stakers[_msgSender()].productCount,
            listingInfos[hash].available
        );

        delete listingInfos[hash];

        /* Log cancel event. */
        emit ListingCancelled(hash);
    }

    function createTransaction(Order memory _order)
        public
        returns (bytes32 hash)
    {
        hash = _requireValidOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.NoTransaction,
            "Order already has been processed"
        );
        // transaction.lastStatusUpdate = block.timestamp;
        // transaction.status = Status.WaitingSeller;
        orderApprove[hash] = true;
        bytes32 listingHash = _hashListing(_order.listing);
        listingInfos[listingHash].orders++;
        if (listingInfos[listingHash].expiration > _order.confirmationTimeout) {
            listingInfos[listingHash].expiration = _order.confirmationTimeout;
        }
        emit TransactionCreated(
            hash,
            _hashListing(_order.listing),
            _order.buyer,
            _order.commissioner,
            _order.token,
            _order.total,
            _order.commission,
            _order.cashback,
            _order.confirmationTimeout
        );
    }

    function cancelTransaction(Order memory _order) public {
        require(
            _msgSender() == _order.listing.seller ||
                _msgSender() == _order.buyer,
            "You must be the buyer or seller"
        );
        bytes32 hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.NoTransaction,
            // transaction.status == Status.WaitingSeller,
            "Order must be waiting for seller"
        );
        delete transaction.lastStatusUpdate;
        delete transaction.status;
        bytes32 listingHash = _hashListing(_order.listing);
        listingInfos[listingHash].orders--;
        listingInfos[listingHash].expiration = _order.listing.expiration;
        emit TransactionCancelled(hash);
    }

    function acceptTransaction(Order memory _order) public {
        require(
            _msgSender() == _order.listing.seller,
            "You must be the seller"
        );
        bytes32 hash = _requireValidOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.NoTransaction,
            // transaction.status == Status.WaitingSeller,
            "Order must be waiting for seller"
        );
        // require(
        //     block.timestamp < transaction.lastStatusUpdate + SELLER_CONFIRMATION_TIMEOUT,
        //     "Order has expired"
        // );

        require(
            _order.token.transferFrom(
                _order.buyer,
                address(this),
                _order.total
            ),
            "Failed to transfer buyer's funds."
        );

        /* After */
        bytes32 listingHash = _hashListing(_order.listing);
        listingInfos[listingHash].available = SafeMath.sub(
            listingInfos[listingHash].available,
            _order.quantity
        );
        listingInfos[hash].expiration = _order.listing.expiration;
        listingInfos[listingHash].orders--;
        transaction.lastStatusUpdate = block.timestamp;
        transaction.status = Status.WaitingConfirmation;
        emit TransactionAccepted(hash);
    }

    /**
        We need to find incentives for a seller to confirmReceipt
     */
    function confirmReceipt(Order memory _order) public {
        bytes32 hash = _hashOrder(_order);
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
            transaction.lastStatusUpdate = block.timestamp;
        } else {
            _finalizeTransaction(_order, false);
        }
    }

    function executeTransaction(Order memory _order) public {
        bytes32 hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation ||
                transaction.status == Status.Warranty ||
                transaction.status == Status.WarrantyConfirmation,
            "Invalid phase"
        );
        bool executed;
        if (
            transaction.status == Status.WaitingConfirmation ||
            transaction.status == Status.WarrantyConfirmation
        ) {
            require(
                block.timestamp >=
                    transaction.lastStatusUpdate +
                        (_order.confirmationTimeout * (1 days)),
                "Timeout time has not passed yet."
            );
            executed = true;
        } else {
            require(
                block.timestamp >=
                    transaction.lastStatusUpdate +
                        (_order.listing.warranty * (1 days)),
                "Timeout time has not passed yet."
            );
        }
        _finalizeTransaction(_order, executed);
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _order The order transaction
     *  @param _executed when to give cashback or not
     */
    function _finalizeTransaction(Order memory _order, bool _executed)
        internal
    {
        bytes32 hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        uint256 refund = transaction.refund;
        uint256 price = _order.total;
        transaction.status = Status.Finalized;
        delete transaction.lastStatusUpdate;
        delete transaction.refund;
        if (refund == price) {
            // Warranty refund, we don't want to pay for any comissions
            require(_order.token.transfer(_order.buyer, refund));
        } else {
            if (_order.protocolFee > 0) {
                price -= _order.protocolFee;
                require(
                    _order.token.transfer(
                        protocolFeeRecipient,
                        _order.protocolFee
                    )
                );
            }

            if (_order.commission > 0) {
                price -= _order.commission;
                require(
                    _order.token.transfer(
                        _order.commissioner,
                        _order.commission
                    )
                );
            }

            if (!_executed) {
                // We are giving a refund, the buyer doesn't need cashback
                uint256 totalRefund = refund > 0 ? refund : _order.cashback;
                if (totalRefund > 0) {
                    price -= totalRefund;
                    require(_order.token.transfer(_order.buyer, totalRefund));
                }
            }

            if (price > 0) {
                require(_order.token.transfer(_order.listing.seller, price));
            }
        }
        emit TransactionFinalized(hash);
    }

    function claimWarranty(Order memory _order) public {
        bytes32 hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(transaction.status == Status.Warranty, "Invalid phase");
        require(_msgSender() == _order.buyer, "You must be buyer");
        require(
            block.timestamp <=
                transaction.lastStatusUpdate +
                    (_order.listing.warranty * (1 days)),
            "Warranty time has timed out."
        );

        transaction.status = Status.WarrantyConfirmation;
        transaction.refund = _order.total;
        transaction.lastStatusUpdate = block.timestamp;
        emit WarrantyClaimed(hash);
    }

    function updateRefund(Order memory _order, uint256 _refund) public {
        require(
            _msgSender() == _order.listing.seller,
            "You must be the listing seller"
        );
        bytes32 hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation,
            "Invalid phase"
        );
        require(
            block.timestamp <=
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)),
            "Confirmation time has timed out."
        );

        require(
            _refund > _order.cashback,
            "Refund must be greater than cashback."
        );
        require(
            _refund + (_order.protocolFee + _order.commission) <= _order.total,
            "Refund can't be greater than total allowed."
        );
        transaction.refund = _refund;
        emit TransactionRefunded(hash, _refund);
    }

    function report(Listing memory _listing)
        public
        payable
        virtual
        returns (bytes32 hash)
    {
        /* CHECKS */
        hash = _requireValidListing(_listing);
        RunningDispute storage dispute = disputes[hash];
        require(
            dispute.status == DisputeStatus.NoDispute ||
                (dispute.status == DisputeStatus.Resolved &&
                    dispute.lastInteraction + GRACE_PERIOD < block.timestamp),
            "Listing has already been reported"
        );
        require(
            _msgSender() != _listing.seller,
            "You can't report yourself. Use cancelListing()"
        );
        uint256 arbCost = arbitrationCost(DisputeType.Report);
        require(
            msg.value >= arbCost,
            "Value must be greater than arbitrationCost"
        );
        Staker storage prosecution = stakers[_msgSender()];
        require(
            block.timestamp > prosecution.blackListExpire,
            "You are not allowed to report listings."
        );
        uint256 availableBalance =
            prosecution.balance - prosecution.lockedTokens;
        if (availableBalance < MINIMUM_STAKED_TOKEN) {
            require(
                marketToken.transferFrom(
                    _msgSender(),
                    address(this),
                    MINIMUM_STAKED_TOKEN - availableBalance
                ),
                "Unable to transfer tokens"
            );
            prosecution.balance += MINIMUM_STAKED_TOKEN - availableBalance;
        }
        /* EFFECTS */

        Staker storage defendant = stakers[_listing.seller];
        prosecution.lockedTokens += MINIMUM_STAKED_TOKEN;
        defendant.lockedTokens += MINIMUM_STAKED_TOKEN;
        _createDispute(
            hash,
            payable(_msgSender()),
            _listing.seller,
            MINIMUM_STAKED_TOKEN,
            marketToken,
            msg.value,
            DisputeType.Report
        );
    }

    function disputeTransaction(Order memory _order)
        public
        payable
        virtual
        returns (bytes32 hash)
    {
        hash = _hashOrder(_order);
        Transaction storage transaction = transactions[hash];
        require(
            transaction.status == Status.WaitingConfirmation ||
                transaction.status == Status.WarrantyConfirmation,
            "Invalid phase"
        );
        require(
            block.timestamp <=
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)),
            "Confirmation time has timed out."
        );
        uint256 arbCost = arbitrationCost(DisputeType.Order);
        require(
            msg.value >= arbCost,
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
            prosecution = _order.listing.seller;
            defendant = _order.buyer;
        }
        transaction.status = Status.InDispute;
        transaction.lastStatusUpdate = block.timestamp;
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
        bytes32 _hash,
        address payable _prosecution,
        address payable _defendant,
        uint256 _amount,
        ERC20 _token,
        uint256 _prosecutionFee,
        DisputeType _disputeType
    ) internal {
        RunningDispute storage dispute = disputes[_hash];
        dispute.prosecution = _prosecution;
        dispute.defendant = _defendant;
        dispute.amount = _amount;
        dispute.prosecutionFee += _prosecutionFee;
        dispute.disputeType = _disputeType;
        /* We know the token is market token, save gas*/
        if (_disputeType != DisputeType.Report) dispute.token = _token;
        dispute.status = DisputeStatus.WaitingDefendant;
        dispute.lastInteraction = block.timestamp;
        dispute.metaEvidenceId = metaEvidenceCount++;
        emit HasToPayFee(_hash, Party.Defendant);
    }

    function disputeTimeout(bytes32 _hash) public {
        RunningDispute storage dispute = disputes[_hash];
        require(
            DisputeStatus.NoDispute < dispute.status &&
                dispute.status < DisputeStatus.DisputeCreated,
            "Dispute is not waiting for any party."
        );
        require(
            block.timestamp - dispute.lastInteraction >= DISPUTE_TIMEOUT,
            "Timeout time has not passed yet."
        );
        // bool success;
        // if (dispute.prosecutionFee != 0) {
        //     uint256 prosecutionFee = dispute.prosecutionFee;
        //     dispute.prosecutionFee = 0;
        //     (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
        // }
        // if (dispute.defendantFee != 0) {
        //     uint256 defendantFee = dispute.defendantFee;
        //     dispute.defendantFee = 0;
        //     (success, ) = dispute.defendant.call{ value: defendantFee }("");
        // }
        if (dispute.status == DisputeStatus.WaitingDefendant) {
            _executeRuling(_hash, uint256(RulingOptions.ProsecutionWins));
        } else {
            _executeRuling(_hash, uint256(RulingOptions.DefendantWins));
        }
    }

    function payArbitrationFee(bytes32 _hash) public payable {
        RunningDispute storage dispute = disputes[_hash];
        uint256 arbCost = arbitrationCost(dispute.disputeType);
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
                dispute.prosecutionFee >= arbCost,
                "The prosecution fee must cover arbitration costs."
            );
            dispute.lastInteraction = block.timestamp;
            if (dispute.defendantFee < arbCost) {
                dispute.status = DisputeStatus.WaitingDefendant;
                emit HasToPayFee(_hash, Party.Defendant);
            } else {
                // The receiver has also paid the fee. We create the dispute.
                _raiseDispute(_hash, arbCost);
            }
        } else {
            dispute.defendantFee += msg.value;
            require(
                dispute.defendantFee >= arbCost,
                "The prosecution fee must cover arbitration costs."
            );
            dispute.lastInteraction = block.timestamp;
            if (dispute.prosecutionFee < arbCost) {
                dispute.status = DisputeStatus.WaitingProsecution;
                emit HasToPayFee(_hash, Party.Prosecution);
            } else {
                // The receiver has also paid the fee. We create the dispute.
                _raiseDispute(_hash, arbCost);
            }
        }
    }

    function _raiseDispute(bytes32 _hash, uint256 _arbitrationCost)
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
    function appeal(bytes32 _hash) public payable virtual;

    function _executeRuling(bytes32 _hash, uint256 _ruling) internal {
        if (disputes[_hash].disputeType == DisputeType.Report) {
            _executeReportRuling(_hash, _ruling);
        } else {
            _executeOrderRuling(_hash, _ruling);
        }
    }

    function _executeOrderRuling(bytes32 _hash, uint256 _ruling) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        RunningDispute storage dispute = disputes[_hash];

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
        /* Finalizing transaction */
        transactions[_hash].status = Status.Finalized;
    }

    function arbitrationCost(DisputeType _type)
        public
        view
        virtual
        returns (uint256 fee);

    function _executeReportRuling(bytes32 _hash, uint256 _ruling) internal {
        require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

        RunningDispute storage dispute = disputes[_hash];
        uint256 amount = dispute.amount;
        uint256 prosecutionFee = dispute.prosecutionFee;
        uint256 defendantFee = dispute.defendantFee;

        dispute.amount = 0;
        dispute.prosecutionFee = 0;
        dispute.defendantFee = 0;
        dispute.status = DisputeStatus.Resolved;
        stakers[dispute.prosecution].lockedTokens -= amount;
        stakers[dispute.defendant].lockedTokens -= amount;
        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint256(RulingOptions.ProsecutionWins)) {
            /* Defendant is always seller */
            stakers[dispute.defendant].productCount -= listingInfos[_hash]
                .available;
            /* Cancelling Listing */
            cancelledOrFinalized[_hash] = true;

            (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
            stakers[dispute.defendant].balance -= amount;
            stakers[dispute.prosecution].balance += amount / 2;
            marketToken.burn(amount - (amount / 2));
        } else if (_ruling == uint256(RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{ value: defendantFee }("");
            stakers[dispute.prosecution].blackListExpire =
                block.timestamp +
                BLACKLIST_TIMEOUT;
            stakers[dispute.prosecution].balance -= amount;
            stakers[dispute.defendant].balance += amount / 2;
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
            stakers[dispute.prosecution].balance -= amount / 2;
            stakers[dispute.defendant].balance -= amount / 2;
        }
    }

    function _burnStake(address stakeHolder) internal {
        uint256 total = stakers[stakeHolder].balance;
        uint256 burn = _calculateTotalFromPercentage(total, PERCENTAGE_BURN);
        marketToken.burn(burn);
        stakers[stakeHolder].balance = total - burn;
    }

    function _validateListing(bytes32 _hash, Listing memory _listing)
        internal
        view
        returns (bool)
    {
        /* Listing has expired */
        if (block.timestamp > _listing.expiration) {
            return false;
        }

        /* Stake owner must have enough tokens */
        Staker storage staker = stakers[_listing.seller];
        if (staker.balance - staker.lockedTokens < MINIMUM_STAKED_TOKEN) {
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (cancelledOrFinalized[_hash]) {
            return false;
        }

        /* Listing must not be in dispute */
        DisputeStatus status = disputes[_hash].status;
        if (
            status != DisputeStatus.NoDispute &&
            status != DisputeStatus.Resolved
        ) {
            return false;
        }

        return true;
    }

    function _validateOrder(bytes32 _hash, Order memory _order)
        internal
        view
        returns (bool)
    {
        /* Token contract must be allowed */
        if (!contracts[address(_order.token)]) {
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (cancelledOrFinalized[_hash]) {
            return false;
        }

        /* Buyer cannot be the seller. */
        if (_order.buyer == _order.listing.seller) {
            return false;
        }

        /* The seller doesn't have enought products */
        if (
            _order.quantity <= 0 ||
            _order.quantity >
            listingInfos[_hashListing(_order.listing)].available
        ) {
            return false;
        }

        /* Commission not enough */
        if (
            _order.commission <
            _calculateTotalFromPercentage(
                _order.total,
                _order.listing.commissionPercentage
            )
        ) {
            return false;
        }

        /* Cashback not enough */
        if (
            _order.cashback <
            _calculateTotalFromPercentage(
                _order.total,
                _order.listing.cashbackPercentage
            )
        ) {
            return false;
        }

        /* Cashback not enough */
        if (
            _order.protocolFee <
            _calculateTotalFromPercentage(_order.total, PROTOCOL_FEE_PERCENTAGE)
        ) {
            return false;
        }

        /* Now enough money for paying taxes */
        if (
            _order.total <
            (_order.cashback + _order.protocolFee + _order.commission)
        ) {
            return false;
        }

        /* Check if order is approved */
        if (orderApprove[_hash]) {
            return true;
        }

        /* Check if buyer is sender */
        return _order.buyer == _msgSender();
    }

    function _hashListing(Listing memory _listing)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(
            abi.encodePacked(
                _listing.ipfsHash,
                _listing.seller,
                _listing.commissionPercentage,
                _listing.warranty,
                _listing.cashbackPercentage,
                _listing.expiration
            )
        );
        return hash;
    }

    function _hashOrder(Order memory _order)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(
            abi.encodePacked(
                _hashListing(_order.listing),
                _order.buyer,
                _order.commissioner,
                _order.token,
                _order.quantity,
                _order.total,
                _order.cashback,
                _order.commission,
                _order.protocolFee,
                _order.confirmationTimeout,
                _order.nonce
            )
        );
        return hash;
    }

    function _requireValidListing(Listing memory _listing)
        internal
        view
        returns (bytes32 hash)
    {
        require(
            _validateListing(hash = _hashListing(_listing), _listing),
            "Invalid listing"
        );
    }

    function _requireValidOrder(Order memory _order)
        internal
        view
        returns (bytes32 hash)
    {
        _requireValidListing(_order.listing);
        require(
            _validateOrder(hash = _hashOrder(_order), _order),
            "Invalid order"
        );
    }

    function _calculateTotalFromPercentage(uint256 _total, uint256 _percentage)
        internal
        pure
        returns (uint256)
    {
        return (_total * _percentage) / INVERSE_BASIS_POINT;
    }
}
