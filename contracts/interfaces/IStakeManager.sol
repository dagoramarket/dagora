// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakeManager {
    struct Staker {
        // The amount of tokens the contract holds for this staker.
        uint256 balance;
        // Total number of tokens the staker can loose in disputes they are.
        uint256 lockedTokens;
    }

    event StakeToken(address indexed sender, uint256 value);
    event UnstakeToken(address indexed sender, uint256 value);

    event LockStake(address indexed sender, uint256 value);
    event UnlockStake(address indexed sender, uint256 value);

    event BurnLockedStake(address indexed sender, uint256 value);

    // Staking
    function stakeTokens(uint256 _value) external;

    function unstakeTokens(uint256 _value) external;

    function lockStake(address _staker, uint256 _value) external;

    function unlockStake(address _staker, uint256 _value) external;

    function burnLockedStake(address _staker, uint256 _percentage) external;

    function balance(address _staker) external view returns (uint256);

    function lockedTokens(address _staker) external view returns (uint256);

    function unlockedTokens(address _staker) external view returns (uint256);
}
