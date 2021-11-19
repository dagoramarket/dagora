//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@opengsn/contracts/src/forwarder/Forwarder.sol";

import "@opengsn/contracts/src/utils/GsnTypes.sol";

// accept everything.
// this paymaster accepts any request.
contract AcceptForwarder is Forwarder {
    // function verify(GsnTypes.RelayData calldata req, bytes calldata sig)
    //     external
    //     view
    //     override
    // {}
    // // validate the signature, and execute the call.
    // function verifyAndCall(GsnTypes.RelayData calldata req, bytes calldata sig)
    //     external
    //     override
    // {}
    // function getNonce(address from) external view override returns (uint256) {}
    // function versionForwarder()
    //     external
    //     view
    //     override
    //     returns (string memory)
    // {}
}
