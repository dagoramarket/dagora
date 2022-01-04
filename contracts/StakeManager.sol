// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IStakeManager.sol";
import "./libraries/PercentageLib.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakeManager is Context, IStakeManager, Ownable {
    mapping(address => Staker) public stakers;
    ERC20Burnable public token;

    address public operator;

    constructor(address _tokenAddress) {
        token = ERC20Burnable(_tokenAddress);
    }

    function setOperator(address _operator) public onlyOwner {
        operator = _operator;
    }

    modifier onlyOperator() {
        require(msg.sender == operator);
        _;
    }

    // Staking
    function stakeTokens(uint256 _value) public override {
        require(token.transferFrom(_msgSender(), address(this), _value));
        stakers[_msgSender()].balance += _value;
        emit StakeToken(_msgSender(), _value);
    }

    function unstakeTokens(uint256 _value) public override {
        require(
            unlockedTokens(_msgSender()) >= _value,
            "You don't have enoght tokens"
        );
        require(token.transfer(_msgSender(), _value));
        stakers[_msgSender()].balance -= _value;
        emit UnstakeToken(_msgSender(), _value);
    }

    function lockStake(address _staker, uint256 _value)
        public
        override
        onlyOperator
    {
        require(stakers[_staker].balance >= _value);
        // require(token.transfer(_msgSender(), _value));
        stakers[_staker].lockedTokens += _value;
        emit LockStake(_staker, _value);
    }

    function unlockStake(address _staker, uint256 _value)
        public
        override
        onlyOperator
    {
        require(stakers[_staker].lockedTokens >= _value);
        // require(token.transferFrom(_msgSender(), address(this), _value));
        stakers[_staker].lockedTokens -= _value;
        emit UnlockStake(_staker, _value);
    }

    function burnLockedStake(address _staker, uint256 _percentage)
        public
        override
        onlyOperator
    {
        uint256 total = stakers[_staker].lockedTokens;
        uint256 burn = PercentageLib.calculateTotalFromPercentage(
            total,
            _percentage
        );
        stakers[_staker].balance -= burn;
        stakers[_staker].lockedTokens -= burn;

        token.burn(burn);

        emit BurnLockedStake(_staker, burn);
    }

    function balance(address _staker) public view override returns (uint256) {
        return stakers[_staker].balance;
    }

    function lockedTokens(address _staker)
        public
        view
        override
        returns (uint256)
    {
        return stakers[_staker].lockedTokens;
    }

    function unlockedTokens(address _staker)
        public
        view
        override
        returns (uint256)
    {
        return stakers[_staker].balance - stakers[_staker].lockedTokens;
    }
}
