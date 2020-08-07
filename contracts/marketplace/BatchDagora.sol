// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Dagora.sol";
import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

abstract contract BatchDagora is Dagora {
    function batchCreateTransaction(
        Order[] memory orders,
        Sig[] memory orderSignatures,
        Sig[] memory listingSignatures
    ) public returns (bytes32[] memory hashes) {
        require(
            orders.length == orderSignatures.length &&
                orderSignatures.length == listingSignatures.length
        );
        hashes = new bytes32[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            hashes[i] = createTransaction(
                orders[i],
                orderSignatures[i],
                listingSignatures[i]
            );
        }
    }

    function batchExecuteTransaction(Order[] memory orders) public {
        for (uint256 i = 0; i < orders.length; i++) {
            executeTransaction(orders[i]);
        }
    }
}
