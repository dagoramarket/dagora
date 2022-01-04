// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DagoraLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IDisputable {
    function transferToken(
        bytes32 _hash,
        address _to,
        uint256 _amount
    ) external;

    function rulingCallback(bytes32 _hash, uint256 _ruling) external;
}
