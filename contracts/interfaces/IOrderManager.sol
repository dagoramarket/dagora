// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DagoraLib.sol";

interface IOrderManager {
    event TransactionCreated(
        bytes32 indexed orderHash,
        bytes32 indexed listingHash,
        address indexed buyer,
        address commissioner,
        ERC20 token,
        uint256 total,
        uint256 commission,
        uint256 cashback,
        uint256 confirmationTimeout
    );

    event TransactionAccepted(bytes32 indexed hash);
    event TransactionCancelled(bytes32 indexed hash);
    event TransactionRefunded(bytes32 indexed hash, uint256 value);
    event TransactionFinalized(bytes32 indexed hash);

    event WarrantyClaimed(bytes32 indexed hash);

    function createOrder(DagoraLib.Order calldata _order)
        external
        returns (bytes32 hash);

    function acceptOrder(DagoraLib.Order calldata _order) external;

    function cancelOrder(DagoraLib.Order calldata _order) external;

    function confirmReceipt(DagoraLib.Order calldata _order) external;

    function executeOrder(DagoraLib.Order calldata _order) external;

    function claimWarranty(DagoraLib.Order calldata _order) external;

    function updateRefund(DagoraLib.Order calldata _order, uint256 _refund)
        external;

    function disputeOrder(DagoraLib.Order calldata _order) external payable;
}
