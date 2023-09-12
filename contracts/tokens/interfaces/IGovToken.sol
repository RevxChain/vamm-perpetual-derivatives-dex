// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGovToken is IERC20 {

    function burn(uint amount) external;

    function burnFrom(address account, uint amount) external;

}