// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library PercentageLib {
    uint256 public constant INVERSE_BASIS_POINT = 10000;

    function calculateTotalFromPercentage(uint256 _total, uint256 _percentage)
        external
        pure
        returns (uint256)
    {
        return (_total * _percentage) / INVERSE_BASIS_POINT;
    }
}
