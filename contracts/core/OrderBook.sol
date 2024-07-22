// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IVAMM.sol";
import "./interfaces/IPermitData.sol";

contract OrderBook is IPermitData, Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
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
    mapping(address => mapping(uint => Order)) public increaseOrders;
    mapping(address => uint) public decreaseOrdersIndex;
    mapping(address => mapping(uint => Order)) public decreaseOrders;
    
    mapping(address => bool) public orderKeepers;
    mapping(address => bool) public whitelistedToken;

    struct Order {
        address user;
        address indexToken;
        uint collateralDelta;
        uint sizeDelta;
        bool long;
        uint triggerPrice;
        bool triggerAboveThreshold;
        uint executionFee;
    }

    modifier whitelisted(address indexToken, bool include) {
        require(whitelistedToken[indexToken] == include, "OrderBook: invalid whitelisted");
        _;
    }

    modifier onlyOrderKeeper() {
        if(executePrivateMode) require(orderKeepers[msg.sender], "OrderBook: invalid handler");
        _;
    }

    function initialize(
        address _vault,
        address _VAMM,
        address _stable,
        address _controller
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(!isInitialized, "OrderBook: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        stable = _stable;
        controller = _controller;

        minExecutionFee = 3e15;
        minOrderWorth = 10e18;
        executePrivateMode = true;
    }

    function setMinExecutionFee(uint newMinExecutionFee) external onlyHandler(dao) {
        require(newMinExecutionFee >= MIN_EXECUTION_FEE, "OrderBook: minExecutionFee underflow");
        minExecutionFee = newMinExecutionFee;
    }

    function setMinOrderWorthUsd(uint newMinOrderWorth) external onlyHandler(dao) {
        require(newMinOrderWorth >= MIN_ORDER_WORTH, "OrderBook: minOrderWorth underflow");
        minOrderWorth = newMinOrderWorth;
    }

    function setOrderKeeper(address keeper, bool set) external onlyHandlers() {
        orderKeepers[keeper] = set;
    }

    function setExecutePrivateMode(bool enableExecutePrivateMode) external onlyHandlers() {
        executePrivateMode = enableExecutePrivateMode;
    }

    function setTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, false) {   
        whitelistedToken[indexToken] = true;
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {   
        whitelistedToken[indexToken] = false;
    }

    function cancelMultiple(uint[] memory increaseOrderIndexes, uint[] memory decreaseOrderIndexes) external {
        for(uint i; increaseOrderIndexes.length > i; i++) cancelIncreaseOrder(increaseOrderIndexes[i]);
        for(uint i; decreaseOrderIndexes.length > i; i++) cancelDecreaseOrder(decreaseOrderIndexes[i]);
    }

    function createIncreaseOrder(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) external payable nonReentrant() whitelisted(indexToken, true) {
        _createIncreaseOrder(
            msg.sender,
            indexToken,
            collateralDelta,
            sizeDelta,
            long,
            triggerPrice,
            triggerAboveThreshold,
            executionFee
        );
    }

    function createIncreaseOrderWithPermit(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee,
        PermitData calldata $
    ) external payable nonReentrant() whitelisted(indexToken, true) {
        address _user = msg.sender;
        require(collateralDelta > 0, "OrderBook: insufficient collateral"); 
        IERC20Permit(stable).safePermit(_user, address(this), collateralDelta.precisionToStable(), $.deadline, $.v, $.r, $.s);  

        _createIncreaseOrder(
            _user,
            indexToken,
            collateralDelta,
            sizeDelta,
            long,
            triggerPrice,
            triggerAboveThreshold,
            executionFee
        );
    }

    function updateIncreaseOrder(
        uint orderIndex, 
        uint sizeDelta, 
        uint triggerPrice, 
        bool triggerAboveThreshold
    ) external nonReentrant() {
        Order storage order = increaseOrders[msg.sender][orderIndex];
        _validateOrderExist(order.user);
        _validateDelta(sizeDelta, order.collateralDelta);

        order.triggerPrice = triggerPrice;
        order.triggerAboveThreshold = triggerAboveThreshold;
        order.sizeDelta = sizeDelta;
    }

    function executeIncreaseOrder(
        address user, 
        uint orderIndex, 
        address payable feeReceiver
    ) external nonReentrant() onlyOrderKeeper() {
        Order memory order = increaseOrders[user][orderIndex];
        _validateOrderExist(order.user);
        IVault(vault).validateLiquidatable(order.user, order.indexToken, order.long, false);

        // _markPrice for event
        (uint _markPrice) = _validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken
        );

        delete increaseOrders[order.user][orderIndex];

        if(order.collateralDelta > 0) IERC20(stable).safeTransfer(vault, order.collateralDelta.precisionToStable());
        _safeETHTransfer(feeReceiver, order.executionFee);

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

    function cancelIncreaseOrder(uint orderIndex) public {
        address payable _user = payable(msg.sender);
        Order memory order = increaseOrders[_user][orderIndex];
        _validateOrderExist(order.user);

        delete increaseOrders[_user][orderIndex];

        IERC20(stable).safeTransfer(_user, order.collateralDelta.precisionToStable());
        _safeETHTransfer(_user, order.executionFee);
    }

    function createDecreaseOrder(
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) external payable nonReentrant() whitelisted(indexToken, true) {
        _validateExecutionFee(executionFee);
        _validateDelta(sizeDelta, collateralDelta);
        address _user = msg.sender;

        decreaseOrders[_user][decreaseOrdersIndex[_user]] = Order({
            user: _user,
            indexToken: indexToken,
            collateralDelta: collateralDelta,
            sizeDelta: sizeDelta,
            long: long,
            triggerPrice: triggerPrice,
            triggerAboveThreshold: triggerAboveThreshold,
            executionFee: executionFee
        });

        decreaseOrdersIndex[_user] += 1;
    }

    function updateDecreaseOrder(
        uint orderIndex,
        uint collateralDelta,
        uint sizeDelta,
        uint triggerPrice,
        bool triggerAboveThreshold
    ) external nonReentrant() {
        Order storage order = decreaseOrders[msg.sender][orderIndex];
        _validateOrderExist(order.user);
        _validateDelta(sizeDelta, collateralDelta);

        order.collateralDelta = collateralDelta;
        order.sizeDelta = sizeDelta;
        order.triggerPrice = triggerPrice;
        order.triggerAboveThreshold = triggerAboveThreshold;   
    }

    function executeDecreaseOrder(
        address user, 
        uint orderIndex, 
        address payable feeReceiver
    ) external nonReentrant() onlyOrderKeeper() {
        Order memory order = decreaseOrders[user][orderIndex];
        _validateOrderExist(order.user);
        IVault(vault).validateLiquidatable(order.user, order.indexToken, order.long, false);

        // _markPrice for event
        (uint _markPrice) = _validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken
        );

        delete decreaseOrders[order.user][orderIndex];

        _safeETHTransfer(feeReceiver, order.executionFee);

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

    function cancelDecreaseOrder(uint orderIndex) public {
        address payable _user = payable(msg.sender);
        Order memory order = decreaseOrders[_user][orderIndex];
        _validateOrderExist(order.user);

        delete decreaseOrders[_user][orderIndex];

        _safeETHTransfer(_user, order.executionFee);
    }

    function _createIncreaseOrder(
        address user,
        address indexToken,
        uint collateralDelta,
        uint sizeDelta,
        bool long,
        uint triggerPrice,
        bool triggerAboveThreshold,
        uint executionFee
    ) internal {
        _validateExecutionFee(executionFee);
        _validateDelta(sizeDelta, collateralDelta);
        
        (, uint _positionSize, , , ,) = IVault(vault).getPosition(user, indexToken, long);
        if(_positionSize == 0) require(collateralDelta >= minOrderWorth, "OrderBook: insufficient collateral");

        if(collateralDelta > 0) IERC20(stable).safeTransferFrom(user, address(this), collateralDelta.precisionToStable());

        increaseOrders[user][increaseOrdersIndex[user]] = Order({
            user: user,
            indexToken: indexToken,
            collateralDelta: collateralDelta,
            sizeDelta: sizeDelta,
            long: long,
            triggerPrice: triggerPrice,
            triggerAboveThreshold: triggerAboveThreshold,
            executionFee: executionFee
        });

        increaseOrdersIndex[user] += 1;
    }

    function _safeETHTransfer(address payable receiver, uint value) internal {
        (bool _success, ) = receiver.call{value: value}(new bytes(0));
        require(_success, "OrderBook: ETH transfer failed");
    }

    function _validatePositionOrderPrice(
        bool triggerAboveThreshold,
        uint triggerPrice,
        address indexToken
    ) internal view returns(uint markPrice) {
        markPrice = IVAMM(VAMM).getPrice(indexToken);
        bool _isPriceValid = triggerAboveThreshold ? markPrice > triggerPrice : markPrice < triggerPrice;
        require(_isPriceValid, "OrderBook: invalid price for execution");
    }

    function _validateExecutionFee(uint executionFee) internal view {
        require(executionFee >= minExecutionFee, "OrderBook: insufficient execution fee");
        require(msg.value == executionFee, "OrderBook: incorrect execution fee transferred");
    }

    function _validateOrderExist(address user) internal pure {
        require(user != address(0), "OrderBook: non-existent order");
    }

    function _validateDelta(uint sizeDelta, uint collateralDelta) internal pure {
        require(sizeDelta > 0 || collateralDelta > 0, "OrderBook: invalid position amounts");
    } 
}