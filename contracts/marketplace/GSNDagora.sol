// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./KlerosDagora.sol";

import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "@opengsn/gsn/contracts/interfaces/IKnowForwarderAddress.sol";

contract GSNDagora is KlerosDagora, BaseRelayRecipient, IKnowForwarderAddress {
    address public trustedPaymaster;

    constructor(
        address _forwarder,
        address _arbitrator,
        address _trustedPaymaster,
        address _token,
        address _protocolFeeRecipient,
        uint256 _feeTimeoutDays,
        uint256 _blacklistTimeoutDays,
        uint256 _protocolFeePercentage,
        uint256 _tokenOwnerFeePercentage,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    )
        public
        KlerosDagora(
            _arbitrator,
            _token,
            _protocolFeeRecipient,
            _feeTimeoutDays,
            _blacklistTimeoutDays,
            _protocolFeePercentage,
            _tokenOwnerFeePercentage,
            _reportExtraData,
            _orderExtraData,
            _ipfsDomain
        )
    {
        trustedForwarder = _forwarder;
        trustedPaymaster = _trustedPaymaster;
    }

    function chargeGasFee(
        Order calldata _order,
        Sig memory orderSig,
        Sig memory listingSig,
        uint256 fee
    ) external returns (bool) {
        require(trustedPaymaster == msg.sender, "Need to be trusted paymaster");
        Transaction storage transaction = transactions[requireValidOrder(
            _order,
            orderSig,
            listingSig
        )];
        require(
            transaction.status > Status.NoTransaction &&
                transaction.status < Status.Finalized
        );
        require(availableToken(_order) >= fee);
        transaction.gasFee += fee;
        _order.token.transferFrom(_msgSender(), msg.sender, fee); // TODO create a cheapier way
        return true;
    }

    function availableToken(Order memory _order) public view returns (uint256) {
        Transaction storage transaction = transactions[hashOrderToSign(_order)];
        return
            _order.total -
            (transaction.refund +
                transaction.gasFee +
                _order.cashback +
                _order.protocolFee +
                _order.stakeHolderFee +
                _order.commission);
    }

    function setTrustedForwarder(address _forwarder) external {
        trustedForwarder = _forwarder;
    }

    function getTrustedForwarder() external override view returns (address) {
        return trustedForwarder;
    }

    function _msgSender()
        internal
        override(Context, BaseRelayRecipient)
        view
        returns (address payable)
    {
        return BaseRelayRecipient._msgSender();
    }

    function versionRecipient() external override view returns (string memory) {
        return "1.0";
    }
}
