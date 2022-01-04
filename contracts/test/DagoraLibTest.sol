// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DagoraLib.sol";

contract DagoraLibTest {
    function hashListing(DagoraLib.Listing memory _listing)
        external
        pure
        returns (bytes32)
    {
        return DagoraLib.hashListing(_listing);
    }

    function hashOrder(DagoraLib.Order memory _order)
        external
        pure
        returns (bytes32)
    {
        return DagoraLib.hashOrder(_order);
    }
}
