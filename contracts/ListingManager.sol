// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/DagoraLib.sol";
import "./interfaces/IListingManager.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IDisputeManager.sol";

contract ListingManager is Context, IListingManager {
    struct ListingInfo {
        /* Products available */
        uint256 available;
        /* Expiration for non-answered transactions */
        uint256 expiration;
        /* Expiration for non-answered transactions */
        uint256 orders;
    }

    /* Listings running in the contract */
    mapping(bytes32 => ListingInfo) public listingInfos;

    mapping(bytes32 => bool) public cancelledListings;

    IStakeManager public stakeManager;
    IDisputeManager public disputeManager;

    uint256 public MINIMUM_STAKED_TOKEN;
    uint256 public PERCENTAGE_BURN;

    modifier onlySeller(DagoraLib.Listing calldata _listing) {
        require(msg.sender == _listing.seller, "You must be the seller");
        _;
    }

    // Listing functions
    function createListing(DagoraLib.Listing calldata _listing)
        public
        override
    {}

    function updateListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) public override onlySeller(_listing) returns (bool) {
        /* CHECKS */

        /* Calculate listing hash. */
        bytes32 hash = requireValidListing(_listing);
        if (
            listingInfos[hash].expiration < block.timestamp &&
            listingInfos[hash].orders > 0
        ) {
            // BURN TOKENS
            stakeManager.burnLockedStake(_msgSender(), PERCENTAGE_BURN);
        }
        address seller = _listing.seller;
        require(
            stakeManager.balance(seller) >= MINIMUM_STAKED_TOKEN,
            "You don't have enoght funds"
        );

        /* Assert listing has not already been approved. */
        /* EFFECTS */
        // stakeManager.addProduct(seller, _quantity);
        // uint256 stakerCount = SafeMath.add(
        //     SafeMath.sub(
        //         stakeManager.productCount(seller),
        //         listingInfos[hash].available
        //     ),
        //     _quantity
        // );

        listingInfos[hash].available = _quantity;
        listingInfos[hash].expiration = _listing.expiration;

        // stakeManager.setProductCount(seller, stakerCount);

        emit ListingUpdated(
            hash,
            _listing.seller,
            _listing.ipfsHash,
            _listing.expiration,
            _quantity
        );
        return true;
    }

    function cancelListing(DagoraLib.Listing calldata _listing)
        public
        override
    {
        /* CHECKS */
        /* Calculate listing hash. */
        bytes32 hash = requireValidListing(_listing);

        /* Assert sender is authorized to cancel listing. */
        // TODO Verify if this is needed
        require(_msgSender() == _listing.seller, "You must be the seller");
        /* EFFECTS */

        if (
            listingInfos[hash].expiration < block.timestamp &&
            listingInfos[hash].orders > 0
        ) {
            // BURN TOKENS
            stakeManager.burnLockedStake(_listing.seller, PERCENTAGE_BURN);
        }

        /* Mark listing as cancelled, preventing it from being matched. */
        cancelledListings[hash] = true;

        // stakeManager.removeProduct(
        //     _listing.seller,
        //     listingInfos[hash].available
        // );

        delete listingInfos[hash];

        /* Log cancel event. */
        emit ListingCancelled(hash);
    }

    function requireValidListing(DagoraLib.Listing memory _listing)
        public
        view
        override
        returns (bytes32 hash)
    {
        require(
            _validateListing(hash = DagoraLib.hashListing(_listing), _listing),
            "Invalid listing"
        );
    }

    function _validateListing(bytes32 _hash, DagoraLib.Listing memory _listing)
        internal
        view
        returns (bool)
    {
        /* Listing has expired */
        if (block.timestamp > _listing.expiration) {
            return false;
        }

        /* Stake owner must have enough tokens */
        if (
            stakeManager.unlockedTokens(_listing.seller) < MINIMUM_STAKED_TOKEN
        ) {
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (cancelledListings[_hash]) {
            return false;
        }

        // TODO Check for disputes
        /* Listing must not be in dispute */
        // DisputeStatus status = disputes[_hash].status;
        // if (
        //     status != DisputeStatus.NoDispute &&
        //     status != DisputeStatus.Resolved
        // ) {
        //     return false;
        // }

        return true;
    }

    function report(DagoraLib.Listing memory _listing)
        public
        payable
        virtual
        override
        returns (bytes32 hash)
    {
        // TODO create report dispute
    }
}
