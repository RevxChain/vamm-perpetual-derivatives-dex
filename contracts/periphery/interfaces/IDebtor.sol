// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtor {

    function sBalance() external view returns(uint);
    function sAmount() external view returns(uint);
    function sFee() external view returns(uint);
    function stable() external view returns(address);
    function vault() external view returns(address);

    function loan(uint amount, bytes calldata data) external payable;

    function executeFlashLoan(uint amount, uint fee, bytes calldata data) external;

    function withdraw(address token, uint amount, address payable receiver) external;

    function calculateActualFee(uint amount) external view returns(uint);

}