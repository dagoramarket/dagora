// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IStakeManager.sol";
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
        require(msg.sender == operator, "Only operator");
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
        stakers[_msgSender()].balance -= _value;

        token.transfer(_msgSender(), _value);

        emit UnstakeToken(_msgSender(), _value);
    }

    function lockStake(address _staker, uint256 _value)
        public
        override
        onlyOperator
    {
        require(stakers[_staker].balance >= _value);

        stakers[_staker].lockedTokens += _value;
        emit LockStake(_staker, _value);
    }

    function unlockStake(address _staker, uint256 _value)
        public
        override
        onlyOperator
    {
        require(stakers[_staker].lockedTokens >= _value);

        stakers[_staker].lockedTokens -= _value;
        emit UnlockStake(_staker, _value);
    }

    function burnLockedStake(address _staker, uint256 _value)
        public
        override
        onlyOperator
    {
        require(stakers[_staker].lockedTokens >= _value);
        stakers[_staker].balance -= _value;
        stakers[_staker].lockedTokens -= _value;

        token.burn(_value);

        emit BurnLockedStake(_staker, _value);
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

    function getTokenAddress() public view override returns (ERC20) {
        return token;
    }
}
