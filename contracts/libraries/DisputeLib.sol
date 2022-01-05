// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IDisputable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library DisputeLib {
    uint8 constant AMOUNT_OF_CHOICES = 2;

    enum Party {
        Prosecution,
        Defendant
    }

    enum RulingOptions {
        NoRuling,
        ProsecutionWins,
        DefendantWins
    }

    enum Status {
        NoDispute,
        WaitingProsecution,
        WaitingDefendant,
        DisputeCreated,
        Resolved
    }

    struct Dispute {
        address payable prosecution;
        address payable defendant;
        ERC20 token;
        uint256 amount;
        uint256 prosecutionFee;
        uint256 defendantFee;
        IDisputable disputable;
        uint256 lastInteraction;
        Status status;
    }
}
