// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/Governable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVAMM.sol";
import "../libraries/Math.sol";

contract OrderBook is Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public constant MIN_EXECUTION_FEE = 15e14;
    uint public constant MIN_ORDER_WORTH = 10e18;

    uint public minExecutionFee;
    uint public minOrderWorth;

    address public vault;
    address public VAMM;
    address public stable;

    bool public isInitialized;
    bool public executePrivateMode; 

    mapping(address => uint) public increaseOrdersIndex;
    mapping(address => mapping(uint => IncreaseOrder)) public increaseOrders;
    mapping(address => uint) public decreaseOrdersIndex;
    mapping(address => mapping(uint => DecreaseOrder)) public decreaseOrders;
    
    mapping(address => bool) public orderKeepers;
    mapping(address => bool) public whitelistedToken;

    struct IncreaseOrder {
        address user;
        address indexToken;
        uint collateralDelta;
        uint sizeDelta;
        bool long;
        uint triggerPrice;
        bool triggerAboveThreshold;
        uint executionFee;
    }

    struct DecreaseOrder {
        address user;
        address indexToken;
        uint collateralDelta;
        uint sizeDelta;
        bool long;
        uint triggerPrice;
        bool triggerAboveThreshold;
        uint executionFee;
    }

    modifier whitelisted(address _indexToken, bool _include) {
        require(whitelistedToken[_indexToken] == _include, "OrderBook: invalid whitelisted");
        _;
    }

    modifier onlyOrderKeeper() {
        if(executePrivateMode) require(orderKeepers[msg.sender] == true, "OrderBook: invalid handler");
        _;
    }

    function initialize(
        address _vault,
        address _VAMM,
        address _stable,
        address _controller,
        uint _minExecutionFee,
        uint _minOrderWorth
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(isInitialized == false, "OrderBook: initialized");
        isInitialized = true;

        require(_minExecutionFee >= MIN_EXECUTION_FEE, "OrderBook: minExecutionFee underflow");
        require(_minOrderWorth >= MIN_ORDER_WORTH, "OrderBook: minOrderWorth underflow");

        vault = _vault;
        VAMM = _VAMM;
        stable = _stable;
        controller = _controller;

        minExecutionFee = _minExecutionFee;
        minOrderWorth = _minOrderWorth;
        executePrivateMode = true;
    }

    function setMinExecutionFee(uint _minExecutionFee) external onlyHandler(dao) {
        require(_minExecutionFee >= MIN_EXECUTION_FEE, "OrderBook: minExecutionFee underflow");
        minExecutionFee = _minExecutionFee;
    }

    function setMinOrderWorthUsd(uint _minOrderWorth) external onlyHandler(dao) {
        require(_minOrderWorth >= MIN_ORDER_WORTH, "OrderBook: minOrderWorth underflow");
        minOrderWorth = _minOrderWorth;
    }

    function setOrderKeeper(address _keeper, bool _bool) external onlyHandlers() {
        orderKeepers[_keeper] = _bool;
    }

    function setExecutePrivateMode(bool _executePrivateMode) external onlyHandlers() {
        executePrivateMode = _executePrivateMode;
    }

    function setTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, false) {   
        whitelistedToken[_indexToken] = true;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {   
        whitelistedToken[_indexToken] = false;
    }

    function cancelMultiple(uint[] memory _increaseOrderIndexes, uint[] memory _decreaseOrderIndexes) external {
        for (uint i = 0; i < _increaseOrderIndexes.length; i++) {
            cancelIncreaseOrder(_increaseOrderIndexes[i]);
        }
        for (uint i = 0; i < _decreaseOrderIndexes.length; i++) {
            cancelDecreaseOrder(_decreaseOrderIndexes[i]);
        }
    }

    function createIncreaseOrder(
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) external payable nonReentrant() whitelisted(_indexToken, true) {
        validateExecutionFee(_executionFee);
        validateDelta(_sizeDelta, _collateralDelta);
        address _user = msg.sender;

        (, uint _positionSize, , , ,) = IVault(vault).getPosition(_user, _indexToken, _long);

        if(_positionSize == 0) require(_collateralDelta >= minOrderWorth, "OrderBook: insufficient collateral");
        if(_collateralDelta > 0) IERC20(stable).safeTransferFrom(_user, address(this), _collateralDelta.precisionToStable());

        _createIncreaseOrder(
            _user,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _long,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
    }

    function _createIncreaseOrder(
        address _user,
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) internal {
        uint _orderIndex = increaseOrdersIndex[_user];
        IncreaseOrder memory order = IncreaseOrder(
            _user,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _long,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
        increaseOrdersIndex[_user] = _orderIndex + 1;
        increaseOrders[_user][_orderIndex] = order;
    }

    function getIncreaseOrder(address _user, uint256 _orderIndex) public view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) {
        IncreaseOrder memory order = increaseOrders[_user][_orderIndex];
        return (
            order.indexToken,
            order.collateralDelta,
            order.sizeDelta,
            order.long,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function updateIncreaseOrder(
        uint _orderIndex, 
        uint _sizeDelta, 
        uint _triggerPrice, 
        bool _triggerAboveThreshold
    ) external nonReentrant() {
        IncreaseOrder storage order = increaseOrders[msg.sender][_orderIndex];
        validateOrderExist(order.user);
        validateDelta(_sizeDelta, order.collateralDelta);

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
    }

    function executeIncreaseOrder(
        address _user, 
        uint _orderIndex, 
        address payable _feeReceiver
    ) external nonReentrant() onlyOrderKeeper() {
        IncreaseOrder memory order = increaseOrders[_user][_orderIndex];
        validateOrderExist(order.user);
        IVault(vault).validateLiquidatable(order.user, order.indexToken, order.long, false);

        // _markPrice for event
        (uint _markPrice) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken
        );

        delete increaseOrders[order.user][_orderIndex];

        if(order.collateralDelta > 0) IERC20(stable).safeTransfer(vault, order.collateralDelta.precisionToStable());
        safeTransfer(_feeReceiver, order.executionFee);

        IVAMM(VAMM).updateIndex(
            order.user, 
            order.indexToken, 
            order.collateralDelta, 
            order.sizeDelta, 
            order.long,
            true,
            false,
            address(0)
        );
    }

    function cancelIncreaseOrder(uint _orderIndex) public {
        address payable _user = payable(msg.sender);
        IncreaseOrder memory order = increaseOrders[_user][_orderIndex];
        validateOrderExist(order.user);

        delete increaseOrders[_user][_orderIndex];

        IERC20(stable).safeTransfer(_user, order.collateralDelta.precisionToStable());
        safeTransfer(_user, order.executionFee);
    }

    function createDecreaseOrder(
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) external payable nonReentrant() whitelisted(_indexToken, true) {
        validateExecutionFee(_executionFee);
        validateDelta(_sizeDelta, _collateralDelta);

        _createDecreaseOrder(
            msg.sender,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _long,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
    }

    function _createDecreaseOrder(
        address _user,
        address _indexToken,
        uint _collateralDelta,
        uint _sizeDelta,
        bool _long,
        uint _triggerPrice,
        bool _triggerAboveThreshold,
        uint _executionFee
    ) internal {
        uint _orderIndex = decreaseOrdersIndex[_user];
        DecreaseOrder memory order = DecreaseOrder(
            _user,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _long,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee
        );
        decreaseOrdersIndex[_user] = _orderIndex + 1;
        decreaseOrders[_user][_orderIndex] = order;
    }

    function getDecreaseOrder(address _user, uint _orderIndex) public view returns(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) {
        DecreaseOrder memory order = decreaseOrders[_user][_orderIndex];
        return (
            order.indexToken,
            order.collateralDelta,
            order.sizeDelta,
            order.long,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee
        );
    }

    function updateDecreaseOrder(
        uint _orderIndex,
        uint _collateralDelta,
        uint _sizeDelta,
        uint _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant() {
        DecreaseOrder storage order = decreaseOrders[msg.sender][_orderIndex];
        validateOrderExist(order.user);
        validateDelta(_sizeDelta, _collateralDelta);

        order.collateralDelta = _collateralDelta;
        order.sizeDelta = _sizeDelta;
        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;   
    }

    function executeDecreaseOrder(
        address _user, 
        uint _orderIndex, 
        address payable _feeReceiver
    ) external nonReentrant() onlyOrderKeeper() {
        DecreaseOrder memory order = decreaseOrders[_user][_orderIndex];
        validateOrderExist(order.user);
        IVault(vault).validateLiquidatable(order.user, order.indexToken, order.long, false);

        // _markPrice for event
        (uint _markPrice) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken
        );

        delete decreaseOrders[order.user][_orderIndex];

        safeTransfer(_feeReceiver, order.executionFee);

        IVAMM(VAMM).updateIndex(
            order.user, 
            order.indexToken, 
            order.collateralDelta, 
            order.sizeDelta, 
            order.long,
            false,
            false,
            address(0)
        );  
    }

    function cancelDecreaseOrder(uint _orderIndex) public {
        address payable _user = payable(msg.sender);
        DecreaseOrder memory order = decreaseOrders[_user][_orderIndex];
        validateOrderExist(order.user);

        delete decreaseOrders[_user][_orderIndex];

        safeTransfer(_user, order.executionFee);
    }

    function safeTransfer(address payable _receiver, uint _value) internal {
        (bool success, ) = _receiver.call{value: _value}(new bytes(0));
        require(success, "OrderBook: ETH transfer failed");
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint _triggerPrice,
        address _indexToken
    ) internal view returns(uint _markPrice) {
        _markPrice = IVAMM(VAMM).getPrice(_indexToken);
        bool _isPriceValid = _triggerAboveThreshold ? _markPrice > _triggerPrice : _markPrice < _triggerPrice;
        require(_isPriceValid, "OrderBook: invalid price for execution");
    }

    function validateExecutionFee(uint _executionFee) internal view {
        require(_executionFee >= minExecutionFee, "OrderBook: insufficient execution fee");
        require(msg.value == _executionFee, "OrderBook: incorrect execution fee transferred");
    }

    function validateOrderExist(address _user) internal pure {
        require(_user != address(0), "OrderBook: non-existent order");
    }

    function validateDelta(uint _sizeDelta, uint _collateralDelta) internal pure {
        require(_sizeDelta > 0 || _collateralDelta > 0, "OrderBook: invalid position amounts");
    } 
}