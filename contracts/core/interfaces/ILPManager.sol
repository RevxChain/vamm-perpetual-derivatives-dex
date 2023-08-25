// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILPManager {

    function vault() external view returns(address);
    function stable() external view returns(address);
    function positionsTracker() external view returns(address);

    function addLiquidity(uint _underlyingAmount) external;

    function removeLiquidity(uint _sTokenAmount) external;

    function calculateUnderlying(uint _sTokenAmount) external view returns(uint underlyingAmount);

}