// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Dagora.sol";
import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

abstract contract BatchDagora is Dagora {
    function batchCreateTransaction(Order[] memory _orders)
        public
        returns (bytes32[] memory hashes)
    {
        hashes = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i++) {
            hashes[i] = createTransaction(_orders[i]);
        }
    }

    function batchAcceptTransaction(Order[] memory _orders) public {
        for (uint256 i = 0; i < _orders.length; i++) {
            acceptTransaction(_orders[i]);
        }
    }

    function batchExecuteTransaction(Order[] memory _orders) public {
        for (uint256 i = 0; i < _orders.length; i++) {
            executeTransaction(_orders[i]);
        }
    }
}
