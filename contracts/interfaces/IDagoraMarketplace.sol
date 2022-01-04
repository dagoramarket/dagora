// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/DagoraLib.sol";

interface IDagoraMarketplace {
    // Only Owner functions

    function updateProtocolFeePercentage(uint256 _protocolFeePercentage)
        external;

    function updateSellerConfirmationTimeout(
        uint256 _sellerConfirmationTimeoutDays
    ) external;

    function updateBlacklistTimeout(uint256 _blacklistTimeoutDays) external;

    function updateDisputeTimeout(uint256 _disputeTimeoutDays) external;

    function updateMinimumStakeToken(uint256 _minimumStakeToken) external;

    // ERC20 Tokens allowed to be used in the Marketplace
    function grantAuthentication(address _erc20Token) external;

    function revokeAuthentication(address _erc20Token) external;
}
