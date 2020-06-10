pragma solidity ^0.6.0;

import "./ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";

contract DagoraToken is ERC20Mintable, ERC20Burnable, ERC20Capped {

    /* 1 billion + 18 decimal plates */
    constructor() ERC20("DagoraToken", "DGR") ERC20Capped(1000000000000000000000000000) public {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Capped, ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}