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
        string ipfsHash;
        address payable seller;
        uint256 expirationBlock;
        // bytes32 extraData; switch from struct to extradata hash
        uint256 commissionPercentage; /* two decimal places */
        uint256 warranty; /* In days */
        uint256 cashbackPercentage; /* two decimal places */
    }

    struct Order {
        Listing listing;
        address payable buyer;
        ERC20 token;
        uint256 total;
        uint256 protocolFee;
        uint256 confirmationTimeout; /* In days */
        uint256 nonce; /* A buyer may want to buy the same product twice */
        // bytes32 extraData; switch from struct to extradata hash
        address payable commissioner;
        uint256 cashback;
        uint256 commission;
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

    function _hashListing(Listing memory _listing)
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
                    _listing.expirationBlock
                )
            );
    }

    function hashListing(Listing memory _listing)
        internal
        pure
        returns (bytes32)
    {
        return _hashListing(_listing);
    }

    function hashOrder(Order memory _order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _hashListing(_order.listing),
                    _order.buyer,
                    _order.commissioner,
                    _order.token,
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
