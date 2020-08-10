// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@opengsn/gsn/contracts/BasePaymaster.sol";
import "@opengsn/gsn/contracts/utils/GsnUtils.sol";
import "@opengsn/gsn/contracts/paymaster/IUniswap.sol";
import "@opengsn/gsn/contracts/interfaces/ITrustedForwarder.sol";
import "../marketplace/Dagora.sol";

contract DagoraPaymaster is BasePaymaster {
    Dagora public dagora;
    IUniswap public uniswap;

    function setUniswap(address _uniswap) external {
        uniswap = IUniswap(_uniswap);
    }

    function setDagora(address _dagora) external {
        dagora = Dagora(_dagora);
    }

    function acceptRelayedCall(
        GSNTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    ) external override view returns (bytes memory) {
        (approvalData);
        ITrustedForwarder forwarder = ITrustedForwarder(
            relayRequest.relayData.forwarder
        );
        forwarder.verify(relayRequest, signature);
        bytes4 func = GsnUtils.getMethodSig(relayRequest.encodedFunction);
        if (func == Dagora.createTransaction.selector) {
            // Dagora.Order memory order;
            // (order, , ) = abi.decode(
            //     relayRequest.encodedFunction, // TODO remove first 4 bytes
            //     (Dagora.Order, Dagora.Sig, Dagora.Sig)
            // );
            // uint256 ethMaxCharge = relayHub.calculateCharge(
            //     maxPossibleGas,
            //     relayRequest.gasData
            // );
            // uint256 tokenPreCharge = uniswap.getTokenToEthOutputPrice(
            //     ethMaxCharge
            // );
            // require(
            //     dagora.availableToken(order) > tokenPreCharge,
            //     "Order must be more expensive to include the gas fee"
            // );
            // require(
            //     order.total < order.token.balanceOf(order.buyer),
            //     "balance too low"
            // );
            // require(
            //     order.total <=
            //         order.token.allowance(order.buyer, address(dagora)),
            //     "allowance too low"
            // );
            // return abi.encode(tokenPreCharge);
        } else {
            revert();
        }
    }

    function preRelayedCall(bytes calldata context)
        external
        override
        returns (bytes32)
    {}

    function postRelayedCall(
        bytes calldata context,
        bool success,
        bytes32 preRetVal,
        uint256 gasUseWithoutPost,
        GSNTypes.GasData calldata gasData
    ) external override {}

    function versionPaymaster() external override view returns (string memory) {
        return "1.0";
    }
}
