// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/DagoraLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IDisputable {
    function onDispute(bytes32 _hash) external;

    function rulingCallback(bytes32 _hash, uint256 _ruling) external;
}
