// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IDisputable.sol";
import "../interfaces/IDisputeManager.sol";
import "../libraries/DisputeLib.sol";

contract TestDisputable is IDisputable {
    IDisputeManager public disputeManager;

    constructor(IDisputeManager _disputeManager) {
        disputeManager = _disputeManager;
    }

    function createDispute(
        bytes32 _hash,
        address payable _prosecution,
        address payable _defendant,
        ERC20 _token,
        uint256 _amount
    ) public payable {
        require(_token.allowance(_defendant, address(this)) >= _amount);
        require(_token.allowance(_prosecution, address(this)) >= _amount);
        disputeManager.createDispute{ value: msg.value }(
            _hash,
            _prosecution,
            _defendant,
            _token,
            _amount
        );
    }

    function onDispute(bytes32 _hash) external override {
        DisputeLib.Dispute memory dispute = disputeManager.getDispute(_hash);
        dispute.token.transferFrom(
            dispute.defendant,
            address(this),
            dispute.amount
        );
        dispute.token.transferFrom(
            dispute.prosecution,
            address(this),
            dispute.amount
        );
    }

    function rulingCallback(bytes32 _hash, uint256 _ruling) external override {
        DisputeLib.Dispute memory dispute = disputeManager.getDispute(_hash);

        if (_ruling == uint256(DisputeLib.RulingOptions.DefendantWins)) {
            dispute.token.transfer(dispute.defendant, dispute.amount * 2);
        } else if (
            _ruling == uint256(DisputeLib.RulingOptions.ProsecutionWins)
        ) {
            dispute.token.transfer(dispute.prosecution, dispute.amount * 2);
        } else {
            dispute.token.transfer(dispute.defendant, dispute.amount);
            dispute.token.transfer(dispute.prosecution, dispute.amount);
        }
    }
}
