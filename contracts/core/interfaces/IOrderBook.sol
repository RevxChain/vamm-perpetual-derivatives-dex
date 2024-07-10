// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPermitData.sol";

interface IOrderBook is IPermitData {

    function minExecutionFee() external view returns(uint);
    function minOrderWorth() external view returns(uint);
    function vault() external view returns(address);
    function VAMM() external view returns(address);
    function stable() external view returns(address);
    function executePrivateMode() external view returns(bool);

    function increaseOrdersIndex(address user) external view returns(uint);
    function decreaseOrdersIndex(address user) external view returns(uint);
    function orderKeepers(address keeper) external view returns(bool);
    function whitelistedToken(address indexToken) external view returns(bool);

    function setMinExecutionFee(uint newMinExecutionFee) external;

    function setMinOrderWorthUsd(uint newMinOrderWorth) external;

    function setOrderKeeper(address keeper, bool set) external;

    function setExecutePrivateMode(bool enableExecutePrivateMode) external;

    function setTokenConfig(address indexToken) external;

    function deleteTokenConfig(address indexToken) external;

    function cancelMultiple(uint[] memory increaseOrderIndexes, uint[] memory decreaseOrderIndexes) external;

    function createIncreaseOrder(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) external payable;

    function createIncreaseOrderWithPermit(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee,
        PermitData calldata $
    ) external payable;

    function getIncreaseOrder(address user, uint256 orderIndex) external view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    );

    function updateIncreaseOrder(
        uint orderIndex, 
        uint sizeDelta, 
        uint triggerPrice, 
        bool triggerAboveThreshold
    ) external;

    function executeIncreaseOrder(address user, uint orderIndex, address payable feeReceiver) external;

    function cancelIncreaseOrder(uint orderIndex) external;

    function createDecreaseOrder(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) external payable;

    function getDecreaseOrder(address user, uint orderIndex) external view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    );

    function updateDecreaseOrder(
        uint orderIndex,
        uint collateralDelta,
        uint sizeDelta,
        uint triggerPrice,
        bool triggerAboveThreshold
    ) external;

    function executeDecreaseOrder(address user, uint orderIndex, address payable feeReceiver) external;

    function cancelDecreaseOrder(uint orderIndex) external;

}