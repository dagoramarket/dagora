// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@opengsn/gsn/contracts/BasePaymaster.sol";
import "@opengsn/gsn/contracts/utils/GsnUtils.sol";
import "@opengsn/gsn/contracts/0x/LibBytesV06.sol";
import "@opengsn/gsn/contracts/paymaster/IUniswap.sol";
import "@opengsn/gsn/contracts/interfaces/ITrustedForwarder.sol";
import "../marketplace/GSNDagora.sol";

contract DagoraPaymaster is BasePaymaster {
    GSNDagora public dagora;
    IUniswap public uniswap;

    //filled by calculatePostGas()
    uint256 public gasUsedByPostWithPreCharge;
    uint256 public gasUsedByPostWithoutPreCharge;

    function setUniswap(address _uniswap) external {
        uniswap = IUniswap(_uniswap);
    }

    function setDagora(address _dagora) external {
        dagora = GSNDagora(_dagora);
    }

    function setPostGasUsage(
        uint256 _gasUsedByPostWithPreCharge,
        uint256 _gasUsedByPostWithoutPreCharge
    ) external onlyOwner {
        gasUsedByPostWithPreCharge = _gasUsedByPostWithPreCharge;
        gasUsedByPostWithoutPreCharge = _gasUsedByPostWithoutPreCharge;
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
            Dagora.Order memory order = abi.decode(
                LibBytesV06.slice(
                    relayRequest.encodedFunction,
                    4,
                    relayRequest.encodedFunction.length
                ),
                (Dagora.Order)
            );
            uint256 ethMaxCharge = relayHub.calculateCharge(
                maxPossibleGas,
                relayRequest.gasData
            );
            uint256 tokenPreCharge = uniswap.getTokenToEthOutputPrice(
                ethMaxCharge
            );
            require(
                dagora.availableToken(order) > tokenPreCharge,
                "Order must be more expensive to include the gas fee"
            );
            require(
                order.total < order.token.balanceOf(order.buyer),
                "balance too low"
            );
            require(
                order.total <=
                    order.token.allowance(order.buyer, address(dagora)),
                "allowance too low"
            );
            return abi.encode(order, tokenPreCharge);
        } else if (func == Dagora.createTransaction.selector) {} else {
            revert();
        }
    }

    function preRelayedCall(bytes calldata context)
        external
        override
        returns (bytes32)
    {
        (Dagora.Order memory order, uint256 tokenPreCharge) = abi.decode(
            context,
            (Dagora.Order, uint256)
        );
        if (tokenPreCharge != 0) {
            dagora.chargeGasFee(order, tokenPreCharge);
        }
        return bytes32(0);
    }

    function postRelayedCall(
        bytes calldata context,
        bool success,
        bytes32 preRetVal,
        uint256 gasUseWithoutPost,
        GSNTypes.GasData calldata gasData
    ) external override {
        (success, preRetVal);

        (Dagora.Order memory order, uint256 tokenPreCharge) = abi.decode(
            context,
            (Dagora.Order, uint256)
        );
        uint256 ethActualCharge;
        uint256 justPost;
        uint256 tokenActualCharge;

        if (tokenPreCharge == 0) {
            justPost = gasUsedByPostWithoutPreCharge;
            ethActualCharge = relayHub.calculateCharge(
                gasUseWithoutPost + justPost,
                gasData
            );
            tokenActualCharge = uniswap.getTokenToEthOutputPrice(
                ethActualCharge
            );

            //no precharge. we pay now entire sum.
            require(
                dagora.chargeGasFee(order, tokenActualCharge),
                "failed transfer"
            );
        } else {
            justPost = gasUsedByPostWithoutPreCharge;
            ethActualCharge = relayHub.calculateCharge(
                gasUseWithoutPost + justPost,
                gasData
            );
            tokenActualCharge = uniswap.getTokenToEthOutputPrice(
                ethActualCharge
            );

            //refund payer
            require(
                order.token.transfer(
                    order.buyer,
                    tokenPreCharge - tokenActualCharge
                ),
                "failed refund"
            );
        }
        //solhint-disable-next-line
        uniswap.tokenToEthSwapOutput(
            ethActualCharge,
            uint256(-1),
            block.timestamp + 60 * 15
        );
        relayHub.depositFor{ value: ethActualCharge }(address(this));
        emit TokensCharged(
            gasUseWithoutPost,
            ethActualCharge,
            tokenActualCharge
        );
    }

    event TokensCharged(
        uint256 gasUseWithoutPost,
        uint256 ethActualCharge,
        uint256 tokenActualCharge
    );

    function versionPaymaster() external override view returns (string memory) {
        return "1.0";
    }
}
