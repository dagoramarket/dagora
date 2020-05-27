pragma solidity ^0.6.0;

import "./ERC20Mintable.sol";
import "./ERC20Burnable.sol";
import "./ERC20Capped.sol";

contract DagoraToken is ERC20Mintable, ERC20Burnable, ERC20Capped {

    constructor() ERC20("DagoraToken", "DGR") ERC20Capped(10000) public {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Capped, ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}