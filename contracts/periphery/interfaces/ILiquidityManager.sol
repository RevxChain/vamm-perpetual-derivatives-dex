// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ILiquidityManagerData.sol";

interface ILiquidityManager is ILiquidityManagerData {

    function setNewImplementation(address newImplementation, string calldata newStrategy, bool claimRewards) external;

    function setStrategySettings(AdditionalSettings calldata addSetup, AdditionalSettings calldata removeSetup) external;

    function setUsageEnabled(bool enabled) external;

    function setAutoUsageEnabled(bool enabled) external;

    function setManualUsageEnabled(bool enabled) external;

    function setTotalPositionsConsider(bool consider) external;

    function manualProvideLiquidity() external;

    function manualRemoveLiquidity() external;

    function getVaultState() external view returns(uint poolAmount, uint availableLiquidity, uint utilizationRate);

}