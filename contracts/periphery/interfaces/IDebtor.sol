// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtor {

    function executeFlashLoan(uint _amount, uint _fee, bytes calldata _data) external;
    
}