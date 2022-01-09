// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IDisputeManager.sol";
import "./interfaces/IDisputable.sol";
import "./libraries/DisputeLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract DisputeManager is Context, IDisputeManager, Ownable {
    mapping(bytes32 => DisputeLib.Dispute) public disputes;

    // Time after a dispute is created before it can be disputed
    uint256 public DISPUTE_TIMEOUT;

    modifier notInDispute(bytes32 _hash) {
        require(!inDispute(_hash));
        _;
    }

    modifier mustBeParty(bytes32 _hash) {
        require(
            _msgSender() == disputes[_hash].prosecution ||
                _msgSender() == disputes[_hash].defendant,
            "Must be party"
        );
        _;
    }

    function updateDisputeTimeout(uint256 _timeout) public onlyOwner {
        DISPUTE_TIMEOUT = _timeout;
    }

    function createDispute(
        bytes32 _hash,
        address payable _prosecution,
        address payable _defendant,
        ERC20 _token,
        uint256 _amount
    ) public payable override notInDispute(_hash) {
        DisputeLib.Dispute storage dispute = disputes[_hash];

        uint256 arbCost = arbitrationCost();
        require(msg.value >= arbCost, "The fee must cover arbitration costs.");

        IDisputable disputable = IDisputable(_msgSender());

        dispute.prosecution = _prosecution;
        dispute.defendant = _defendant;
        dispute.amount = _amount;
        dispute.prosecutionFee += msg.value;
        dispute.disputable = disputable;
        dispute.status = DisputeLib.Status.WaitingDefendant;
        dispute.lastInteraction = block.timestamp;
        dispute.token = _token;

        disputable.onDispute(_hash);

        emit HasToPayFee(_hash, DisputeLib.Party.Defendant);
    }

    function disputeTimeout(bytes32 _hash) public override {
        DisputeLib.Dispute storage dispute = disputes[_hash];
        require(
            DisputeLib.Status.NoDispute < dispute.status &&
                dispute.status < DisputeLib.Status.DisputeCreated,
            "Dispute is not waiting for any party."
        );
        require(
            block.timestamp - dispute.lastInteraction >= DISPUTE_TIMEOUT,
            "Timeout time has not passed yet."
        );
        if (dispute.status == DisputeLib.Status.WaitingDefendant) {
            _executeRuling(
                _hash,
                uint256(DisputeLib.RulingOptions.ProsecutionWins)
            );
        } else {
            _executeRuling(
                _hash,
                uint256(DisputeLib.RulingOptions.DefendantWins)
            );
        }
    }

    function payArbitrationFee(bytes32 _hash)
        public
        payable
        override
        mustBeParty(_hash)
    {
        DisputeLib.Dispute storage dispute = disputes[_hash];
        uint256 arbCost = arbitrationCost();
        require(
            dispute.status < DisputeLib.Status.DisputeCreated,
            "Dispute has already been created."
        );
        address feePayer = _msgSender();
        uint256 feePaid = 0;
        if (feePayer == dispute.prosecution) {
            dispute.prosecutionFee += msg.value;
            feePaid = dispute.prosecutionFee;
        } else {
            dispute.defendantFee += msg.value;
            feePaid = dispute.defendantFee;
        }

        require(feePaid >= arbCost, "The fee must cover arbitration costs.");

        DisputeLib.Status newStatus;
        DisputeLib.Party hasToPayParty;
        uint256 otherPartyFee;

        if (feePayer == dispute.prosecution) {
            otherPartyFee = dispute.defendantFee;
            newStatus = DisputeLib.Status.WaitingDefendant;
            hasToPayParty = DisputeLib.Party.Defendant;
        } else {
            otherPartyFee = dispute.prosecutionFee;
            newStatus = DisputeLib.Status.WaitingProsecution;
            hasToPayParty = DisputeLib.Party.Prosecution;
        }

        if (otherPartyFee < arbCost) {
            dispute.status = newStatus;
            dispute.lastInteraction = block.timestamp;
            emit HasToPayFee(_hash, hasToPayParty);
        } else {
            // dispute.arbCost = arbCost;
            // The receiver has also paid the fee. We create the dispute.
            _raiseDispute(_hash, arbCost);
        }
    }

    function _executeRuling(bytes32 _hash, uint256 _ruling) internal {
        DisputeLib.Dispute storage dispute = disputes[_hash];

        uint256 prosecutionFee = dispute.prosecutionFee;
        uint256 defendantFee = dispute.defendantFee;
        IDisputable disputable = dispute.disputable;
        dispute.status = DisputeLib.Status.Resolved;

        // Give the arbitration fee back.
        // Note that we use `send` to prevent a party from blocking the execution.
        bool success = false;
        if (_ruling == uint256(DisputeLib.RulingOptions.ProsecutionWins)) {
            (success, ) = dispute.prosecution.call{ value: prosecutionFee }("");
        } else if (_ruling == uint256(DisputeLib.RulingOptions.DefendantWins)) {
            (success, ) = dispute.defendant.call{ value: defendantFee }("");
        } else {
            // `senderFee` and `receiverFee` are equal to the arbitration cost.
            uint256 splitArbitrationFee = prosecutionFee / 2;
            /* Give 1 wei more to defendant in case of even number */
            (success, ) = dispute.defendant.call{
                value: defendantFee - splitArbitrationFee
            }("");
            (success, ) = dispute.prosecution.call{
                value: splitArbitrationFee
            }("");
        }
        /* Finalizing transaction */
        disputable.rulingCallback(_hash, _ruling);

        delete dispute.amount;
        delete dispute.prosecutionFee;
        delete dispute.defendantFee;
        delete dispute.disputable;
        delete dispute.token;
        delete dispute.amount;
    }

    function _raiseDispute(bytes32 _hash, uint256 _arbitrationCost)
        internal
        virtual
    {
        DisputeLib.Dispute storage dispute = disputes[_hash];
        dispute.status = DisputeLib.Status.DisputeCreated;

        // Refund sender if it overpaid.
        bool success;
        if (dispute.prosecutionFee > _arbitrationCost) {
            uint256 extraFeeProsecution = dispute.prosecutionFee -
                _arbitrationCost;
            dispute.prosecutionFee = _arbitrationCost;
            (success, ) = dispute.prosecution.call{
                value: extraFeeProsecution
            }("");
        }

        // Refund receiver if it overpaid.
        if (dispute.defendantFee > _arbitrationCost) {
            uint256 extraFeeDefendant = dispute.defendantFee - _arbitrationCost;
            dispute.defendantFee = _arbitrationCost;
            (success, ) = dispute.defendant.call{ value: extraFeeDefendant }(
                ""
            );
        }
    }

    function inDispute(bytes32 _hash) public view override returns (bool) {
        DisputeLib.Dispute storage dispute = disputes[_hash];
        return
            dispute.status > DisputeLib.Status.NoDispute &&
            dispute.status < DisputeLib.Status.Resolved;
    }

    function getDispute(bytes32 _hash)
        external
        view
        override
        returns (DisputeLib.Dispute memory)
    {
        DisputeLib.Dispute storage dispute = disputes[_hash];
        return dispute;
    }

    function arbitrationCost() public view virtual override returns (uint256);
}
