// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILPManager {

    function vault() external view returns(address);
    function stable() external view returns(address);
    function positionsTracker() external view returns(address);
    function baseRemoveFee() external view returns(uint); 
    function baseProviderFee() external view returns(uint); 
    function profitProviderFee() external view returns(uint); 
    function feeReserves() external view returns(uint);
    function lockDuration() external view returns(uint);  

    function lastAdded(address user) external view returns(uint);

    function setBaseRemoveFee(uint newBaseRemoveFee) external;

    function setBaseProviderFee(uint newBaseProviderFee) external;

    function setProfitProviderFee(uint newProfitProviderFee) external;

    function setLockDuration(uint newLockDuration) external;

    function withdrawFees() external;

    function addLiquidity(uint underlyingAmount) external returns(uint lpAmount);

    function removeLiquidity(uint sTokenAmount) external returns(uint underlyingAmount);

    function calculateUnderlying(uint sTokenAmount) external view returns(uint underlyingAmount);

}