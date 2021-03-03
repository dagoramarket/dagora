// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./BatchDagora.sol";
import "../arbitration/Arbitrator.sol";
import "../arbitration/IArbitrable.sol";

contract KlerosDagora is BatchDagora, IArbitrable {
    Arbitrator public arbitrator; // Address of the arbitrator contract.
    bytes public reportExtraData; // Extra data to set up the arbitration.
    bytes public orderExtraData; // Extra data to set up the arbitration.
    string public ipfsDomain;

    constructor(
        address _arbitrator,
        address _token,
        address _protocolFeeRecipient,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    ) public Dagora(_token, _protocolFeeRecipient) {
        arbitrator = Arbitrator(_arbitrator);
        reportExtraData = _reportExtraData;
        orderExtraData = _orderExtraData;
        ipfsDomain = _ipfsDomain;
    }

    function report(Listing memory _listing)
        public
        override
        payable
        returns (bytes32 hash)
    {
        hash = Dagora.report(_listing);
        emit MetaEvidence(
            disputes[hash].metaEvidenceId,
            string(abi.encodePacked(ipfsDomain, _listing.ipfsHash))
        );
    }

    function disputeTransaction(Order memory _order)
        public
        override
        payable
        returns (bytes32 hash)
    {
        hash = Dagora.disputeTransaction(_order);
        emit MetaEvidence(
            disputes[hash].metaEvidenceId,
            string(abi.encodePacked(ipfsDomain, _order.listing.ipfsHash))
        );
    }

    function _raiseDispute(bytes32 _hash, uint256 _arbitrationCost)
        internal
        override
    {
        RunningDispute storage dispute = disputes[_hash];
        dispute.status = DisputeStatus.DisputeCreated;
        uint256 disputeId = arbitrator.createDispute{ value: _arbitrationCost }(
            AMOUNT_OF_CHOICES,
            dispute.disputeType == DisputeType.Order
                ? orderExtraData
                : reportExtraData
        );
        disputeIDtoHash[disputeId] = _hash;
        emit Dispute(
            arbitrator,
            disputeId,
            dispute.metaEvidenceId,
            dispute.metaEvidenceId
        );
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

    function submitEvidence(bytes32 _hash, string memory _evidence)
        public
        override
    {
        RunningDispute storage dispute = disputes[_hash];
        require(
            _msgSender() == dispute.prosecution ||
                _msgSender() == dispute.defendant,
            "The caller must be the prosecution or the defendant."
        );
        require(
            dispute.disputeType == DisputeType.Order,
            "Evidences are only allowed for orders disputes."
        );
        require(
            dispute.status < DisputeStatus.Resolved,
            "Must not send evidence if the dispute is resolved."
        );

        emit Evidence(
            arbitrator,
            dispute.metaEvidenceId,
            _msgSender(),
            _evidence
        );
    }

    function rule(uint256 _disputeID, uint256 _ruling) public override {
        bytes32 hash = disputeIDtoHash[_disputeID];
        RunningDispute storage dispute = disputes[hash];
        require(
            _msgSender() == address(arbitrator),
            "The caller must be the arbitrator."
        );
        require(
            dispute.status == DisputeStatus.DisputeCreated,
            "The dispute has already been resolved."
        );
        emit Ruling(Arbitrator(_msgSender()), _disputeID, _ruling);
        _executeRuling(hash, _ruling);
    }

    function appeal(bytes32 _hash) public override payable {
        RunningDispute storage dispute = disputes[_hash];
        require(
            dispute.disputeType == DisputeType.Order,
            "Appeals are only allowed for orders disputes."
        );

        arbitrator.appeal{ value: msg.value }(
            dispute.disputeId,
            orderExtraData
        );
    }

    function arbitrationCost(DisputeType _type)
        public
        override
        view
        returns (uint256 fee)
    {
        require(_type > DisputeType.None);
        if (_type == DisputeType.Report) {
            fee = arbitrator.arbitrationCost(reportExtraData);
        } else if (_type == DisputeType.Order) {
            fee = arbitrator.arbitrationCost(orderExtraData);
        }
    }
}
