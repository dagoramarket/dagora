// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DisputeLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IDisputeManager {
    event HasToPayFee(bytes32 indexed _hashI, DisputeLib.Party _party);

    function createDispute(
        bytes32 _hash,
        address payable _prosecution,
        address payable _defendant,
        ERC20 _token,
        uint256 _amount
    ) external payable;

    function disputeTimeout(bytes32 _hash) external;

    function payArbitrationFee(bytes32 _hash) external payable;

    function submitEvidence(bytes32 _hash, string calldata _evidence) external;

    function appeal(bytes32 _hash) external payable;

    function arbitrationCost() external view returns (uint256);
}
