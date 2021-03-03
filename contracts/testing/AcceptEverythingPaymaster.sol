//SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@opengsn/gsn/contracts/BasePaymaster.sol";

import "@opengsn/gsn/contracts/utils/GSNTypes.sol";

// accept everything.
// this paymaster accepts any request.
contract AcceptEverythingPaymaster is BasePaymaster {
    function versionPaymaster()
        external
        view
        virtual
        override
        returns (string memory)
    {
        return "2.0.0-alpha.1+opengsn.accepteverything.ipaymaster";
    }

    function acceptRelayedCall(
        GSNTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    ) external view override returns (bytes memory) {}

    function preRelayedCall(bytes calldata context)
        external
        override
        returns (bytes32)
    {
        (context);
        return "";
    }

    function postRelayedCall(
        bytes calldata context,
        bool success,
        bytes32 preRetVal,
        uint256 gasUseWithoutPost,
        GSNTypes.GasData calldata gasData
    ) external virtual override {
        (context, success, preRetVal, gasUseWithoutPost, gasData);
    }
}
