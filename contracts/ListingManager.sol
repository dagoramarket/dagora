// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/DagoraLib.sol";
import "./libraries/PercentageLib.sol";
import "./libraries/DisputeLib.sol";
import "./interfaces/IListingManager.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IDisputeManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ListingManager is Context, IListingManager, IDisputable, Ownable {
    // struct ListingInfo {
    //     /* Products available */
    //     uint256 available;
    // }

    // /* Listings running in the contract */
    // mapping(bytes32 => ListingInfo) public listingInfos;

    mapping(bytes32 => bool) public cancelledListings;

    IStakeManager public stakeManager;
    IDisputeManager public disputeManager;

    uint256 public MINIMUM_STAKED_TOKEN;
    uint256 public PERCENTAGE_BURN;

    constructor(
        IStakeManager _stakeManager,
        IDisputeManager _disputeManager,
        uint256 _MINIMUM_STAKED_TOKEN,
        uint256 _PERCENTAGE_BURN
    ) {
        stakeManager = _stakeManager;
        disputeManager = _disputeManager;
        MINIMUM_STAKED_TOKEN = _MINIMUM_STAKED_TOKEN;
        PERCENTAGE_BURN = _PERCENTAGE_BURN;
    }

    modifier onlySeller(DagoraLib.Listing calldata _listing) {
        require(_msgSender() == _listing.seller, "You must be seller");
        _;
    }

    modifier onlyDisputeManager() {
        require(
            _msgSender() == address(disputeManager),
            "Only dispute manager can call this function"
        );
        _;
    }

    // Listing functions
    function createListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) public override onlySeller(_listing) returns (bytes32 hash) {
        /* Calculate listing hash. */
        hash = requireValidListing(_listing);

        emit ListingCreated(
            hash,
            _listing.seller,
            _listing.ipfsHash,
            _listing.expiration,
            _quantity
        );
    }

    function updateListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) public override onlySeller(_listing) returns (bytes32 hash) {
        /* CHECKS */

        /* Calculate listing hash. */
        hash = requireValidListing(_listing);

        emit ListingUpdated(hash, _quantity);
    }

    function cancelListing(DagoraLib.Listing calldata _listing)
        public
        override
        onlySeller(_listing)
    {
        /* CHECKS */
        /* Calculate listing hash. */
        bytes32 hash = requireValidListing(_listing);

        /* EFFECTS */

        cancelledListings[hash] = true;

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

        if (stakeManager.balance(_listing.seller) < MINIMUM_STAKED_TOKEN) {
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (cancelledListings[_hash]) {
            return false;
        }

        /* Listing must not be in dispute */
        if (disputeManager.inDispute(_hash)) {
            return false;
        }

        return true;
    }

    function report(DagoraLib.Listing memory _listing)
        public
        payable
        virtual
        override
        returns (bytes32 hash)
    {
        /* CHECKS */
        require(_msgSender() != _listing.seller, "You can't report yourself");
        /* Calculate listing hash. */
        hash = requireValidListing(_listing);

        address payable prosecution = payable(_msgSender());
        address payable defendant = _listing.seller;
        uint256 amount = PercentageLib.calculateTotalFromPercentage(
            stakeManager.balance(defendant),
            PERCENTAGE_BURN
        );
        disputeManager.createDispute{ value: msg.value }(
            hash,
            prosecution,
            defendant,
            stakeManager.getTokenAddress(),
            amount
        );
    }

    function onDispute(bytes32 _hash) external override onlyDisputeManager {
        DisputeLib.Dispute memory dispute = disputeManager.getDispute(_hash);
        stakeManager.lockStake(dispute.defendant, dispute.amount);
    }

    // Maybe create an incentive for the reporter to not report for denying the listing (even tho he loses money doing so)
    function rulingCallback(bytes32 _hash, uint256 _ruling)
        external
        override
        onlyDisputeManager
    {
        DisputeLib.Dispute memory dispute = disputeManager.getDispute(_hash);
        if (_ruling == uint256(DisputeLib.RulingOptions.DefendantWins)) {
            stakeManager.unlockStake(dispute.defendant, dispute.amount);
        } else if (
            _ruling == uint256(DisputeLib.RulingOptions.ProsecutionWins)
        ) {
            stakeManager.burnLockedStake(dispute.defendant, dispute.amount);
        } else {
            uint256 split = dispute.amount / 2;
            stakeManager.unlockStake(dispute.defendant, dispute.amount - split);
            stakeManager.burnLockedStake(dispute.defendant, split);
        }
    }
}
