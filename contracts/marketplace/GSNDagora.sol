// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./KlerosDagora.sol";

import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";

contract GSNDagora is KlerosDagora, BaseRelayRecipient {
    constructor(
        address _forwarder,
        address _arbitrator,
        address _token,
        address _protocolFeeRecipient,
        uint256 _feeTimeoutDays,
        uint256 _blacklistTimeoutDays,
        uint256 _protocolFeePercentage,
        uint256 _tokenOwnerFeePercentage,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    )
        public
        KlerosDagora(
            _arbitrator,
            _token,
            _protocolFeeRecipient,
            _feeTimeoutDays,
            _blacklistTimeoutDays,
            _protocolFeePercentage,
            _tokenOwnerFeePercentage,
            _reportExtraData,
            _orderExtraData,
            _ipfsDomain
        )
    {
        trustedForwarder = _forwarder;
    }

    function _msgSender()
        internal
        virtual
        override(Context, BaseRelayRecipient)
        view
        returns (address payable)
    {
        return BaseRelayRecipient._msgSender();
    }

    function versionRecipient()
        external
        virtual
        override
        view
        returns (string memory)
    {
        return "1.0";
    }
}
