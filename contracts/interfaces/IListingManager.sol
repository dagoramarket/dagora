// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DagoraLib.sol";

interface IListingManager {
    event ListingCreated(
        bytes32 indexed hash,
        address indexed seller,
        string ipfs,
        uint256 expirationBlock,
        uint256 commissionPercentage,
        uint256 cashbackPercentage,
        uint256 warranty,
        uint256 quantity
    );

    event ListingUpdated(bytes32 indexed hash, uint256 quantity);
    event ListingCancelled(bytes32 indexed hash);

    event ListingReported(bytes32 indexed hash);

    event ListingReportResult(bytes32 indexed hash, uint256 result);

    // Listing functions
    function createListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) external returns (bytes32 hash);

    function updateListing(
        DagoraLib.Listing calldata _listing,
        uint256 _quantity
    ) external returns (bytes32 hash);

    function cancelListing(DagoraLib.Listing calldata _listing) external;

    function report(DagoraLib.Listing calldata _listing)
        external
        payable
        returns (bytes32 hash);

    function requireValidListing(DagoraLib.Listing calldata _listing)
        external
        view
        returns (bytes32 hash);
}
