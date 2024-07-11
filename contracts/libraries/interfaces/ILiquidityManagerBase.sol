// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILiquidityManagerBase {

    function provideLiquidity(uint amount) external returns(bool success, uint usedAmount);

    function removeLiquidity(uint amount) external returns(bool success, uint earnedAmount);

    function checkUsage(bool autoUsage) external view returns(bool allowed, uint amount);
    
    function checkRemove(bool autoUsage) external view returns(bool allowed, uint amount);

}