// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./arbitration/Disputable.sol";
import "./interfaces/IOrderManager.sol";
import "./interfaces/IListingManager.sol";
import "./interfaces/IDisputeManager.sol";
import "./libraries/DagoraLib.sol";
import "./libraries/PercentageLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract OrderManager is Context, IOrderManager, Disputable {
    IListingManager public listingManager;

    mapping(bytes32 => bool) public cancelledOrders;
    /* Transactions running in the contract */
    mapping(bytes32 => DagoraLib.Transaction) public transactions; // Order Hash to Transaction
    /* Order approve */
    // mapping(bytes32 => bool) public orderApprove;

    uint256 public PROTOCOL_FEE_PERCENTAGE;
    // uint256 public SELLER_CONFIRMATION_TIMEOUT;

    address public protocolFeeRecipient;

    modifier onlyBuyerOrSeller(DagoraLib.Order calldata _order) {
        require(
            _msgSender() == _order.listing.seller ||
                _msgSender() == _order.buyer,
            "You must be the buyer or seller"
        );
        _;
    }

    modifier onlySeller(DagoraLib.Order calldata _order) {
        require(_msgSender() == _order.listing.seller, "You must be seller");
        _;
    }

    modifier onlyBuyer(DagoraLib.Order calldata _order) {
        require(_msgSender() == _order.buyer, "You must be buyer");
        _;
    }

    constructor(
        IListingManager _listingManager,
        IDisputeManager _disputeManager,
        address _protocolFeeRecipient,
        uint256 _protocolFeePercentage
    ) Disputable(_disputeManager) {
        listingManager = _listingManager;
        protocolFeeRecipient = _protocolFeeRecipient;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
        // SELLER_CONFIRMATION_TIMEOUT = _sellerConfirmationTimeout;
    }

    function createOrder(DagoraLib.Order calldata _order)
        public
        override
        returns (bytes32 _hash)
    {
        bytes32 listingHash;
        (_hash, listingHash) = requireValidOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.NoTransaction,
            "Order already has been processed"
        );
        transaction.lastStatusUpdate = block.timestamp;
        transaction.status = DagoraLib.Status.WaitingSeller;
        require(
            _order.token.transferFrom(
                _order.buyer,
                address(this),
                _order.total
            ),
            "Failed to transfer buyer's funds."
        );
        // orderApprove[_hash] = true;

        emit TransactionCreated(
            _hash,
            listingHash,
            _order.buyer,
            _order.commissioner,
            _order.token,
            _order.total,
            _order.commission,
            _order.cashback,
            _order.confirmationTimeout
        );
    }

    function acceptOrder(DagoraLib.Order calldata _order)
        public
        override
        onlySeller(_order)
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.WaitingSeller,
            "Order must be waiting for seller"
        );
        // require(
        //     block.timestamp < transaction.lastStatusUpdate + SELLER_CONFIRMATION_TIMEOUT,
        //     "Order has expired"
        // );

        transaction.lastStatusUpdate = block.timestamp;
        transaction.status = DagoraLib.Status.WaitingConfirmation;

        emit TransactionAccepted(_hash);
    }

    function cancelOrder(DagoraLib.Order calldata _order)
        public
        override
        onlyBuyerOrSeller(_order)
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.WaitingSeller,
            "Order must be waiting for seller"
        );
        delete transaction.lastStatusUpdate;
        delete transaction.status;

        emit TransactionCancelled(_hash);
    }

    function confirmReceipt(DagoraLib.Order calldata _order) public override {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            (transaction.status == DagoraLib.Status.WaitingConfirmation &&
                _msgSender() == _order.buyer) ||
                (transaction.status == DagoraLib.Status.WarrantyConfirmation &&
                    _msgSender() == _order.listing.seller),
            "You must be seller or buyer in the right phase."
        );
        if (transaction.refund == 0 && _order.listing.warranty > 0) {
            transaction.status = DagoraLib.Status.Warranty;
            transaction.lastStatusUpdate = block.timestamp;
        } else {
            _finalizeTransaction(_order, false);
        }
    }

    function executeOrder(DagoraLib.Order calldata _order) public override {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        bool waitingForConfirmation = transaction.status ==
            DagoraLib.Status.WaitingConfirmation ||
            transaction.status == DagoraLib.Status.WarrantyConfirmation;
        require(
            waitingForConfirmation ||
                transaction.status == DagoraLib.Status.Warranty,
            "Invalid phase"
        );
        require(
            block.timestamp >=
                transaction.lastStatusUpdate +
                    ((
                        waitingForConfirmation
                            ? _order.confirmationTimeout
                            : _order.listing.warranty
                    ) * (1 days)),
            "Timeout time has not passed yet."
        );
        _finalizeTransaction(_order, waitingForConfirmation);
    }

    function claimWarranty(DagoraLib.Order calldata _order)
        public
        override
        onlyBuyer(_order)
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.Warranty,
            "Invalid phase"
        );
        require(
            block.timestamp <=
                transaction.lastStatusUpdate +
                    (_order.listing.warranty * (1 days)),
            "Warranty time has timed out."
        );
        transaction.status = DagoraLib.Status.WarrantyConfirmation;
        transaction.refund = _order.total;
        transaction.lastStatusUpdate = block.timestamp;
        emit WarrantyClaimed(_hash);
    }

    function updateRefund(DagoraLib.Order calldata _order, uint256 _refund)
        public
        override
        onlySeller(_order)
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.WaitingConfirmation,
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
        emit TransactionRefunded(_hash, _refund);
    }

    function disputeOrder(DagoraLib.Order calldata _order)
        public
        payable
        override
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        require(
            transaction.status == DagoraLib.Status.WaitingConfirmation ||
                transaction.status == DagoraLib.Status.WarrantyConfirmation,
            "Invalid phase"
        );
        require(
            block.timestamp <=
                transaction.lastStatusUpdate +
                    (_order.confirmationTimeout * (1 days)),
            "Confirmation time has timed out."
        );
        address payable prosecution;
        address payable defendant;
        if (transaction.status == DagoraLib.Status.WaitingConfirmation) {
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
        transaction.status = DagoraLib.Status.InDispute;
        transaction.lastStatusUpdate = block.timestamp;
        disputeManager.createDispute{ value: msg.value }(
            _hash,
            prosecution,
            defendant,
            _order.token,
            _order.total
        );
    }

    // IDisputable Functions

    function onDispute(bytes32 _hash) public override onlyDisputeManager {}

    function rulingCallback(bytes32 _hash, uint256 _ruling)
        public
        override
        onlyDisputeManager
    {}

    // Internal Functions

    function _finalizeTransaction(DagoraLib.Order memory _order, bool _executed)
        internal
    {
        bytes32 _hash = DagoraLib.hashOrder(_order);
        DagoraLib.Transaction storage transaction = transactions[_hash];
        uint256 refund = transaction.refund;
        uint256 price = _order.total;
        transaction.status = DagoraLib.Status.Finalized;
        delete transaction.lastStatusUpdate;
        delete transaction.refund;
        if (refund == price) {
            // Warranty refund, we don't want to pay for any comissions
            _order.token.transfer(_order.buyer, refund);
        } else {
            if (_order.protocolFee > 0) {
                price -= _order.protocolFee;
                _order.token.transfer(protocolFeeRecipient, _order.protocolFee);
            }

            if (_order.commission > 0) {
                price -= _order.commission;
                _order.token.transfer(_order.commissioner, _order.commission);
            }

            if (!_executed) {
                // We are giving a refund, the buyer doesn't need cashback
                uint256 totalRefund = refund > 0 ? refund : _order.cashback;
                if (totalRefund > 0) {
                    price -= totalRefund;
                    _order.token.transfer(_order.buyer, totalRefund);
                }
            }

            if (price > 0) {
                _order.token.transfer(_order.listing.seller, price);
            }
        }
        emit TransactionFinalized(_hash);
    }

    function requireValidOrder(DagoraLib.Order memory _order)
        public
        view
        returns (bytes32 _hash, bytes32 listingHash)
    {
        listingHash = listingManager.requireValidListing(_order.listing);
        _hash = DagoraLib.hashOrder(_order);
        require(_validateOrder(_order), "Invalid order");
    }

    function _validateOrder(DagoraLib.Order memory _order)
        internal
        view
        returns (bool)
    {
        /* TODO Token contract must be allowed */
        // if (!contracts[address(_order.token)]) {
        //     return false;
        // }

        /* Listing must have not been canceled or already filled. */
        // if (cancelledOrders[_hash]) {
        //     console.log("Order canceled");
        //     return false;
        // }

        /* Buyer cannot be the seller. */
        if (_order.buyer == _order.listing.seller) {
            console.log("Buyer cannot be the seller");
            return false;
        }

        /* Commission not enough */
        if (
            _order.commission <
            PercentageLib.calculateTotalFromPercentage(
                _order.total,
                _order.listing.commissionPercentage
            )
        ) {
            console.log("Commission not enough");
            return false;
        }

        /* Cashback not enough */
        if (
            _order.cashback <
            PercentageLib.calculateTotalFromPercentage(
                _order.total,
                _order.listing.cashbackPercentage
            )
        ) {
            console.log("Cashback not enough");
            return false;
        }

        /* ProtocolFee not enough */
        if (
            _order.protocolFee <
            PercentageLib.calculateTotalFromPercentage(
                _order.total,
                PROTOCOL_FEE_PERCENTAGE
            )
        ) {
            console.log("ProtocolFee not enough");
            return false;
        }

        /* Now enough money for paying taxes */
        if (
            _order.total <
            (_order.cashback + _order.protocolFee + _order.commission)
        ) {
            console.log("Not enough money for paying taxes");
            return false;
        }

        /* Check if order is approved */
        // if (orderApprove[_hash]) {
        //     return true;
        // }

        /* Check if buyer is sender */
        return _order.buyer == _msgSender();
    }
}
