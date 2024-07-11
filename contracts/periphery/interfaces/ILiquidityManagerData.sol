// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILiquidityManagerData {

    function minRemoveAllowedShare() external view returns(uint);
    function initStableAmount() external view returns(uint);
    function aTokenAmount() external view returns(uint);
    function referralCode() external view returns(uint);
    function aToken() external view returns(address);
    function targetPool() external view returns(address);
    function rewardsController() external view returns(address);
    function extraReward() external view returns(address);
    function newImplEnabled() external view returns(bool);
    function allowedSupplyRateA() external view returns(uint);
    function allowedAmountA() external view returns(uint);
    function allowedShareA() external view returns(uint);
    function utilizationRateKinkA() external view returns(uint);
    function availableLiquidityKinkA() external view returns(uint);
    function poolAmountKinkA() external view returns(uint);
    function totalPositionsDeltaKinkA() external view returns(uint);
    function allowedSupplyRateR() external view returns(uint);
    function allowedAmountR() external view returns(uint);
    function allowedShareR() external view returns(uint);
    function utilizationRateKinkR() external view returns(uint);
    function availableLiquidityKinkR() external view returns(uint);
    function poolAmountKinkR() external view returns(uint);
    function totalPositionsDeltaKinkR() external view returns(uint);

    /// @custom:storage-location erc7201:RevxChain.storage.LiquidityManagerData.AddSettings && RevxChain.storage.LiquidityManagerData.RemoveSettings 
    struct AdditionalSettings {
        uint _allowedSupplyRate;
        uint _allowedAmount;
        uint _allowedShare;
        uint _utilizationRateKink; 
        uint _availableLiquidityKink;
        uint _poolAmountKink;
        uint _totalPositionsDeltaKink;
    }

}