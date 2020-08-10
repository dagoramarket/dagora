//SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@opengsn/gsn/contracts/interfaces/ITrustedForwarder.sol";

import "@opengsn/gsn/contracts/utils/GSNTypes.sol";

// accept everything.
// this paymaster accepts any request.
contract AcceptForwarder is ITrustedForwarder {
    function verify(GSNTypes.RelayRequest calldata req, bytes calldata sig)
        external
        override
        view
    {}

    // validate the signature, and execute the call.
    function verifyAndCall(
        GSNTypes.RelayRequest calldata req,
        bytes calldata sig
    ) external override {}

    function getNonce(address from) external override view returns (uint256) {}

    function versionForwarder()
        external
        override
        view
        returns (string memory)
    {}
}
