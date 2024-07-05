// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract GovToken is ERC20Burnable {

    constructor(address to, uint amount) ERC20("GovToken", "GToken") {
        _mint(to, amount);
    }
}