// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initSupply) ERC20("MockERC20", "MCK", 18) {
        _mint(msg.sender, initSupply);
    }
    function mint(uint256 amount, address receiver) public {
        _mint(receiver, amount);
    }
}