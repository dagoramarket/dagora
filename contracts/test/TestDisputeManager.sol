// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DisputeManager.sol";
import "hardhat/console.sol";

contract TestDisputeManager is DisputeManager {
    event DisputeCreated(bytes32 indexed _hash);
    event Appeal(bytes32 indexed _hash, address indexed _appealer);
    event Evidence(
        bytes32 indexed _hash,
        address indexed _evidenceHolder,
        string data
    );

    uint256 public arbCost;

    function updateArbCost(uint256 _arbCost) public onlyOwner {
        arbCost = _arbCost;
    }

    function rule(bytes32 _hash, uint256 _ruling) public onlyOwner {
        _executeRuling(_hash, _ruling);
    }

    function submitEvidence(bytes32 _hash, string calldata data)
        external
        override
        mustBeParty(_hash)
    {
        emit Evidence(_hash, _msgSender(), data);
    }

    function appeal(bytes32 _hash)
        external
        payable
        override
        mustBeParty(_hash)
    {
        emit Appeal(_hash, _msgSender());
    }

    function _raiseDispute(bytes32 _hash, uint256 _arbCost) internal override {
        super._raiseDispute(_hash, _arbCost);
        emit DisputeCreated(_hash);
    }

    function arbitrationCost() public view override returns (uint256) {
        return arbCost;
    }
}
