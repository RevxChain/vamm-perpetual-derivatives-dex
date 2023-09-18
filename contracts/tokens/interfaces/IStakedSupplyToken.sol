// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakedSupplyToken is IERC20 {

    function mint(address account, uint amount) external;

    function burn(uint amount) external;

    function burnFrom(address account, uint amount) external;

}