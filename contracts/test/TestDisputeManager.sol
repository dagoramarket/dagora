// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DisputeManager.sol";
import "hardhat/console.sol";

contract TestDisputeManager is DisputeManager {
    function submitEvidence(bytes32, string calldata) external view override {
        console.log("submitEvidence");
    }

    function appeal(bytes32) external payable override {
        console.log("Appeal");
    }

    function _raiseDispute(bytes32, uint256) internal view override {
        console.log("_raiseDispute");
    }

    function arbitrationCost() public pure override returns (uint256) {
        return 0;
    }
}
