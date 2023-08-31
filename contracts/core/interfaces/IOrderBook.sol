// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOrderBook {

    function minExecutionFee() external view returns(uint);
    function minOrderWorth() external view returns(uint);
    function vault() external view returns(address);
    function VAMM() external view returns(address);
    function stable() external view returns(address);
    function executePrivateMode() external view returns(bool);
    function increaseOrdersIndex(address _user) external view returns(uint);
    function decreaseOrdersIndex(address _user) external view returns(uint);
    function orderKeepers(address _keeper) external view returns(bool);
    function whitelistedToken(address _indexToken) external view returns(bool);

    function setMinExecutionFee(uint _minExecutionFee) external;

    function setMinOrderWorthUsd(uint _minOrderWorth) external;

    function setOrderKeeper(address _keeper, bool _bool) external;

    function setExecutePrivateMode(bool _executePrivateMode) external;

    function setTokenConfig(address _indexToken) external;

    function deleteTokenConfig(address _indexToken) external;

    function cancelMultiple(uint[] memory _increaseOrderIndexes, uint[] memory _decreaseOrderIndexes) external;

    function createIncreaseOrder(
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) external payable;

    function getIncreaseOrder(address _user, uint256 _orderIndex) external view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    );

    function updateIncreaseOrder(
        uint _orderIndex, 
        uint _sizeDelta, 
        uint _triggerPrice, 
        bool _triggerAboveThreshold
    ) external;

    function executeIncreaseOrder(address _user, uint _orderIndex, address payable _feeReceiver) external;

    function cancelIncreaseOrder(uint _orderIndex) external;

    function createDecreaseOrder(
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) external payable;

    function getDecreaseOrder(address _user, uint _orderIndex) external view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    );

    function updateDecreaseOrder(
        uint _orderIndex,
        uint _collateralDelta,
        uint _sizeDelta,
        uint _triggerPrice,
        bool _triggerAboveThreshold
    ) external;

    function executeDecreaseOrder(address _user, uint _orderIndex, address payable _feeReceiver) external;

    function cancelDecreaseOrder(uint _orderIndex) external;

}