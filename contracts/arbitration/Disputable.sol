// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IDisputable.sol";
import "../interfaces/IDisputeManager.sol";
import "../libraries/DisputeLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Disputable is IDisputable, Ownable {
    IDisputeManager public disputeManager;

    constructor(IDisputeManager _disputeManager) {
        disputeManager = _disputeManager;
    }

    modifier onlyDisputeManager() {
        require(
            _msgSender() == address(disputeManager),
            "Only dispute manager can call this function"
        );
        _;
    }

    function updateDisputeManager(IDisputeManager _disputeManager)
        public
        onlyOwner
    {
        disputeManager = _disputeManager;
    }

    function onDispute(bytes32 _hash)
        external
        virtual
        override
        onlyDisputeManager
    {}

    function rulingCallback(bytes32 _hash, uint256 _ruling)
        external
        virtual
        override
        onlyDisputeManager
    {}
}
