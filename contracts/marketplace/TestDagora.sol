// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./GSNDagora.sol";

contract TestDagora is GSNDagora {
    constructor(
        address _arbitrator,
        address _trustedPaymaster,
        address _token,
        address _protocolFeeRecipient,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    )
        public
        GSNDagora(
            _arbitrator,
            _trustedPaymaster,
            _token,
            _protocolFeeRecipient,
            _reportExtraData,
            _orderExtraData,
            _ipfsDomain
        )
    {}

    function requireValidListing(Listing memory _listing)
        public
        view
        returns (bool)
    {
        return _requireValidListing(_listing) != 0x0;
    }

    function hashListing(Listing memory _listing)
        public
        pure
        returns (bytes32 hash)
    {
        return _hashListing(_listing);
    }
}
