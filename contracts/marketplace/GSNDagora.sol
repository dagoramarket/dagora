// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./KlerosDagora.sol";

import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "@opengsn/gsn/contracts/interfaces/IKnowForwarderAddress.sol";

contract GSNDagora is KlerosDagora, BaseRelayRecipient, IKnowForwarderAddress {
    address public trustedPaymaster;

    constructor(
        address _arbitrator,
        address _trustedPaymaster,
        address _token,
        address _protocolFeeRecipient,
        bytes memory _reportExtraData,
        bytes memory _orderExtraData,
        string memory _ipfsDomain
    )
        public
        KlerosDagora(
            _arbitrator,
            _token,
            _protocolFeeRecipient,
            _reportExtraData,
            _orderExtraData,
            _ipfsDomain
        )
    {
        trustedPaymaster = _trustedPaymaster;
    }

    function chargeGasFee(Order calldata _order, uint256 _fee)
        external
        returns (bool)
    {
        require(trustedPaymaster == msg.sender, "Need to be trusted paymaster");
        Transaction storage transaction = transactions[_requireValidOrder(
            _order
        )];
        require(
            transaction.status > Status.NoTransaction &&
                transaction.status < Status.Finalized
        );
        require(availableToken(_order) >= _fee);
        transaction.gasFee += _fee;
        _order.token.transferFrom(_msgSender(), msg.sender, _fee); // TODO create a cheapier way
        return true;
    }

    function availableToken(Order memory _order) public view returns (uint256) {
        Transaction storage transaction = transactions[_hashOrder(_order)];
        return
            _order.total -
            (transaction.refund +
                transaction.gasFee +
                _order.cashback +
                _order.protocolFee +
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
