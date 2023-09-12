// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILPManager {

    function vault() external view returns(address);
    function stable() external view returns(address);
    function positionsTracker() external view returns(address);
    function feeReserves() external view returns(uint); 

    function withdrawFees() external;

    function addLiquidity(uint _underlyingAmount) external returns(uint lpAmount);

    function removeLiquidity(uint _sTokenAmount) external returns(uint underlyingAmount);

    function calculateUnderlying(uint _sTokenAmount) external view returns(uint underlyingAmount);

}