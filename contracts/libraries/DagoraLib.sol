// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library DagoraLib {
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
        uint256 expiration;
        // bytes32 extraData; switch from struct to extradata hash
        uint256 commissionPercentage; /* two decimal places */
        uint256 warranty; /* In days */
        uint256 cashbackPercentage; /* two decimal places */
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

    function _hashListing(Listing calldata _listing)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    _listing.ipfsHash,
                    _listing.seller,
                    _listing.commissionPercentage,
                    _listing.warranty,
                    _listing.cashbackPercentage,
                    _listing.expiration
                )
            );
    }

    function hashListing(Listing calldata _listing)
        external
        pure
        returns (bytes32)
    {
        return _hashListing(_listing);
    }

    function hashOrder(Order calldata _order) external pure returns (bytes32) {
        return
            keccak256(
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
    }
}
