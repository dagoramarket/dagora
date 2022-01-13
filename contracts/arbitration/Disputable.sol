// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IDisputable.sol";
import "../interfaces/IDisputeManager.sol";
import "../libraries/DisputeLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Disputable is IDisputable, Ownable {
    mapping(address => bool) public managerAllowed;
    IDisputeManager public disputeManager;

    constructor(IDisputeManager _disputeManager) {
        updateDisputeManager(_disputeManager);
    }

    modifier onlyDisputeManager() {
        require(
            managerAllowed[_msgSender()],
            "Only dispute manager can call this function"
        );
        _;
    }

    function updateDisputeManager(IDisputeManager _disputeManager)
        public
        onlyOwner
    {
        disputeManager = _disputeManager;
        managerAllowed[address(disputeManager)] = true;
    }

    function onDispute(bytes32) external virtual override onlyDisputeManager {}

    function rulingCallback(bytes32, uint256)
        external
        virtual
        override
        onlyDisputeManager
    {}
}
