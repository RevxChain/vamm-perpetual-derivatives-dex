// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILiquidityManager {

    function minRemoveAllowedShare() external view returns(uint);
    function initStableAmount() external view returns(uint);
    function aTokenAmount() external view returns(uint);
    function referralCode() external view returns(uint);
    function implementation() external view returns(address);
    function vault() external view returns(address);
    function stable() external view returns(address);
    function positionsTracker() external view returns(address);
    function target() external view returns(address);
    function aToken() external view returns(address);
    function strategy() external view returns(string memory);
    function usageEnabled() external view returns(bool);
    function autoUsageEnabled() external view returns(bool);
    function manualUsageEnabled() external view returns(bool);
    function totalPositionsConsider() external view returns(bool);
    function active() external view returns(bool);
    function newImplEnabled() external view returns(bool);

    struct Settings {
        uint allowedSupplyRate;
        uint allowedAmount;
        uint allowedShare;
        uint utilizationRateKink; 
        uint availableLiquidityKink;
        uint poolAmountKink;
        uint totalPositionsDeltaKink;
    }

    function setNewImplementation(address newImplementation, string calldata newStrategy) external;

    function setStrategySettings(Settings calldata addSetup, Settings calldata removeSetup) external;

    function setUsageEnabled(bool enabled) external;

    function setAutoUsageEnabled(bool enabled) external;

    function setManualUsageEnabled(bool enabled) external;

    function setTotalPositionsConsider(bool consider) external;

    function provideLiquidity(uint amount) external;

    function removeLiquidity(uint amount) external returns(bool success, uint earnedAmount);

    function manualProvideLiquidity() external;

    function manualRemoveLiquidity() external;

    function checkUsage(bool autoUsage) external view returns(bool allowed, uint amount);
    
    function checkRemove(bool autoUsage) external view returns(bool allowed, uint amount);

    function getVaultState() external view returns(uint poolAmount, uint availableLiquidity, uint utilizationRate);

}