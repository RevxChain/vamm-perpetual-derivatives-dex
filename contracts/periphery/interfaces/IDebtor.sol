// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtor {

    function executeFlashLoan(uint amount, uint fee, bytes calldata data) external;
    
}