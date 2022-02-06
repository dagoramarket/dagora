// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./arbitration/Disputable.sol";
import "./libraries/DagoraLib.sol";
import "./libraries/PercentageLib.sol";
import "./libraries/DisputeLib.sol";
import "./interfaces/IListingManager.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IDisputeManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract ListingManager is Context, IListingManager, Disputable {
    mapping(bytes32 => bool) public approvedListings;

    IStakeManager public stakeManager;

    uint256 public MINIMUM_STAKED_TOKEN;
    uint256 public PERCENTAGE_BURN;

    constructor(
        IStakeManager _stakeManager,
        IDisputeManager _disputeManager,
        uint256 _MINIMUM_STAKED_TOKEN,
        uint256 _PERCENTAGE_BURN
    ) Disputable(_disputeManager) {
        stakeManager = _stakeManager;
        MINIMUM_STAKED_TOKEN = _MINIMUM_STAKED_TOKEN;
        PERCENTAGE_BURN = _PERCENTAGE_BURN;
    }

    modifier onlySeller(DagoraLib.Listing calldata _listing) {
        require(_msgSender() == _listing.seller, "You must be seller");
        _;
    }

    // Listing functions
    function createListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) public override onlySeller(_listing) returns (bytes32 hash) {
        /* Calculate listing hash. */
        hash = requireValidListing(_listing);

        approvedListings[hash] = true;

        emit ListingCreated(
            hash,
            _listing.seller,
            _listing.ipfsHash,
            _listing.expiration,
            _listing.commissionPercentage,
            _listing.cashbackPercentage,
            _listing.warranty,
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
        bytes32 hash = DagoraLib.hashListing(_listing);

        /* EFFECTS */

        approvedListings[hash] = false;

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
            console.log("Listing expired");
            return false;
        }

        if (stakeManager.balance(_listing.seller) < MINIMUM_STAKED_TOKEN) {
            console.log("Not enough tokens");
            return false;
        }

        /* Listing must not be in dispute */
        if (disputeManager.inDispute(_hash)) {
            console.log("Listing in dispute");
            return false;
        }

        /* Listing must have not been canceled or already filled. */
        if (approvedListings[_hash]) {
            return true;
        }

        return _msgSender() == _listing.seller;
    }

    function report(DagoraLib.Listing memory _listing)
        public
        payable
        virtual
        override
        returns (bytes32 _hash)
    {
        /* CHECKS */
        require(_msgSender() != _listing.seller, "You can't report yourself");
        /* Calculate listing hash. */
        _hash = requireValidListing(_listing);

        address payable prosecution = payable(_msgSender());
        address payable defendant = _listing.seller;
        uint256 amount = PercentageLib.calculateTotalFromPercentage(
            stakeManager.balance(defendant),
            PERCENTAGE_BURN
        );
        require(
            stakeManager.unlockedTokens(prosecution) >= amount,
            "Not enough tokens"
        );
        disputeManager.createDispute{ value: msg.value }(
            _hash,
            prosecution,
            defendant,
            stakeManager.getTokenAddress(),
            amount
        );
        emit ListingReported(_hash);
    }

    function onDispute(bytes32 _hash) external override onlyDisputeManager {
        DisputeLib.Dispute memory dispute = IDisputeManager(_msgSender())
            .getDispute(_hash);
        stakeManager.lockStake(dispute.prosecution, dispute.amount);
        stakeManager.lockStake(dispute.defendant, dispute.amount);
    }

    // Maybe create an incentive for the reporter to not report for denying the listing (even tho he loses money doing so)
    function rulingCallback(bytes32 _hash, uint256 _ruling)
        external
        override
        onlyDisputeManager
    {
        DisputeLib.Dispute memory dispute = IDisputeManager(_msgSender())
            .getDispute(_hash);
        if (_ruling == uint256(DisputeLib.RulingOptions.DefendantWins)) {
            stakeManager.unlockStake(dispute.defendant, dispute.amount);
            stakeManager.burnLockedStake(dispute.prosecution, dispute.amount);
        } else if (
            _ruling == uint256(DisputeLib.RulingOptions.ProsecutionWins)
        ) {
            stakeManager.unlockStake(dispute.prosecution, dispute.amount);
            stakeManager.burnLockedStake(dispute.defendant, dispute.amount);
        } else {
            uint256 split = dispute.amount / 2;
            stakeManager.unlockStake(dispute.defendant, dispute.amount - split);
            stakeManager.unlockStake(
                dispute.prosecution,
                dispute.amount - split
            );
            stakeManager.burnLockedStake(dispute.defendant, split);
            stakeManager.burnLockedStake(dispute.prosecution, split);
        }
        emit ListingReportResult(_hash, _ruling);
    }
}
