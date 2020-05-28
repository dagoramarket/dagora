// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Dagora.sol";

contract TestDagora is Dagora {

    constructor(address _arbitrator,
                address _token,
                address _protocolFeeRecipient,
                uint _feeTimeoutDays,
                uint _blacklistTimeoutDays,
                uint _protocolFeePercentage,
                uint _tokenOwnerFeePercentage,
                bytes memory _reportExtraData,
                bytes memory _orderExtraData,
                string memory _ipfsDomain)
                Dagora(_arbitrator,
                        _token,
                        _protocolFeeRecipient,
                        _feeTimeoutDays,
                        _blacklistTimeoutDays,
                        _protocolFeePercentage,
                        _tokenOwnerFeePercentage,
                        _reportExtraData,
                        _orderExtraData,
                        _ipfsDomain) public {
    }

    function _requireValidListing(Listing memory _listing, Sig memory sig)
        public
        view
        returns (bool)
    {
        return requireValidListing(_listing, sig) != 0x0;
    }

    function _hashListing(Listing memory listing)
        public
        pure
        returns (bytes32 hash)
    {
        return hashListing(listing);
    }

    function _hashListingToSign(Listing memory listing)
        public
        pure
        returns (bytes32 hash)
    {
        return hashListingToSign(listing);
    }

    function _ecrecover(bytes32 msgHash, Sig memory sig) public pure returns (address) {
        return ecrecover(msgHash, sig.v, sig.r, sig.s);
    }
}