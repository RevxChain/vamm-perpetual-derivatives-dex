// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IVault.sol";
import "./interfaces/IPositionsTracker.sol";
import "../libraries/Governable.sol";

contract VAMM is Governable {

    uint public constant PRECISION = 10000;
    uint public constant ACCURACY = 1e18;
    
    uint public constant MIN_LIQUIDITY = 2e27;
    uint public constant MAX_ALLOWED_PRICE_DEVIATION = 100; 
    uint public constant MIN_LIQUIDITY_UPDATE_DELAY = 12 hours;

    uint public allowedPriceDeviation;

    address public vault;
    address public positionsTracker;
    address public controller;

    bool public isInitialized;

    mapping(address => bool) public whitelistedToken;
    mapping(address => bool) public routers;
    mapping(address => Pair) public pairs;

    struct Pair {
        uint indexAmount;
        uint stableAmount;
        uint liquidity;
        uint lastUpdateTime;
    }

    modifier onlyRouter() {
        require(routers[msg.sender] == true, "VAMM: invalid handler");
        _;
    }

    modifier whitelisted(address _indexToken, bool _include) {
        require(whitelistedToken[_indexToken] == _include, "VAMM: invalid whitelisted");
        _;
    }

    function initialize(
        address _vault,
        address _positionsTracker,
        address _marketRouter,
        address _orderBook,
        address _controller
    ) external onlyHandler(gov) {  
        require(isInitialized == false, "VAMM: initialized");
        isInitialized = true;

        vault = _vault;
        positionsTracker = _positionsTracker;
        controller = _controller;
        routers[_marketRouter] = true;
        routers[_orderBook] = true;

        allowedPriceDeviation = 30;
    }

    function setAllowedPriceDeviation(uint _allowedPriceDeviation) external onlyHandler(dao) {
        require(MAX_ALLOWED_PRICE_DEVIATION >= _allowedPriceDeviation, "VAMM: price deviation exceeded");
        allowedPriceDeviation = _allowedPriceDeviation;
    }

    function setTokenConfig(
        address _indexToken,
        uint _indexAmount,
        uint _stableAmount,
        uint _referencePrice
    ) external onlyHandler(controller) whitelisted(_indexToken, false) {      
        validateLiquidity(_indexAmount, _stableAmount);
        validatePriceDeviation(_indexToken, _indexAmount, _stableAmount, _referencePrice, true);

        Pair storage pair = pairs[_indexToken]; 
        pair.indexAmount = _indexAmount;
        pair.stableAmount = _stableAmount;
        pair.liquidity = _indexAmount * _stableAmount;
        pair.lastUpdateTime = block.timestamp;

        whitelistedToken[_indexToken] = true;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {   
        whitelistedToken[_indexToken] = false;

        delete pairs[_indexToken];
    }

    function updateIndex(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta,
        bool _long,
        bool _increase,
        bool _liquidation,
        address _feeReceiver
    ) external onlyRouter() whitelisted(_indexToken, true) {   
        Pair storage pair = pairs[_indexToken]; 

        uint _markPrice = getPrice(_indexToken);

        if(_sizeDelta > 0){
            uint _newStableAmount;
            uint _newIndexAmount;
            (_newStableAmount, _newIndexAmount, _markPrice) = preCalculatePrice(_indexToken, _sizeDelta, _increase, _long);

            pair.stableAmount = _newStableAmount;
            pair.indexAmount = _newIndexAmount;
        }

        if(_increase){
            IVault(vault).increasePosition(
                _user, 
                _indexToken, 
                _collateralDelta, 
                _sizeDelta,
                _long,
                _markPrice
            );

            IPositionsTracker(positionsTracker).increaseTotalSizes(_indexToken, _sizeDelta, _markPrice, _long);
        } else {
            !_liquidation ? 
            IVault(vault).decreasePosition(
                _user, 
                _indexToken, 
                _collateralDelta, 
                _sizeDelta,
                _long,
                _markPrice
            ) :
            IVault(vault).liquidatePosition(
                _user,  
                _indexToken,
                _sizeDelta,
                _long, 
                _feeReceiver
            );

            IPositionsTracker(positionsTracker).decreaseTotalSizes(_indexToken, _sizeDelta, _markPrice, _long);
        } 
    }

    // test function
    function setPrice(
        address _indexToken, 
        uint _indexAmount,
        uint _stableAmount
    ) external {
        Pair storage pair = pairs[_indexToken]; 
        pair.indexAmount = _indexAmount;
        pair.stableAmount = _stableAmount;
        pair.liquidity = _indexAmount * _stableAmount;
    }

    function setLiquidity(
        address _indexToken, 
        uint _indexAmount, 
        uint _stableAmount
    ) external onlyHandlers() whitelisted(_indexToken, true) {
        validateLiquidity(_indexAmount, _stableAmount);
        Pair storage pair = pairs[_indexToken]; 
        require(block.timestamp >= pair.lastUpdateTime + MIN_LIQUIDITY_UPDATE_DELAY, "VAMM: premature update");
        validatePriceDeviation(_indexToken, _indexAmount, _stableAmount, 0, false);

        pair.indexAmount = _indexAmount;
        pair.stableAmount = _stableAmount;
        pair.liquidity = _indexAmount * _stableAmount;
        pair.lastUpdateTime = block.timestamp;
    }

    function getData(address _indexToken) external view returns(uint, uint, uint, uint) {
        Pair memory pair = pairs[_indexToken]; 
        return (pair.indexAmount, pair.stableAmount, pair.liquidity, pair.lastUpdateTime);
    }

    function getPrice(address _indexToken) public view returns(uint) {
        return pairs[_indexToken].stableAmount * ACCURACY / pairs[_indexToken].indexAmount;
    }

    function preCalculatePrice(
        address _indexToken, 
        uint _sizeDelta, 
        bool _increase, 
        bool _long
    ) public view returns(uint newStableAmount, uint newIndexAmount, uint markPrice) {
        uint _outputIndexed; 
        Pair memory pair = pairs[_indexToken]; 

        if(_increase && !_long || !_increase && _long){
            newStableAmount = pair.stableAmount - _sizeDelta;
            newIndexAmount = pair.liquidity / newStableAmount;
            _outputIndexed = newIndexAmount - pair.indexAmount;
        } else {
            newStableAmount = pair.stableAmount + _sizeDelta;
            newIndexAmount = pair.liquidity / newStableAmount;
            _outputIndexed = pair.indexAmount - newIndexAmount;
        }

        markPrice = _sizeDelta * ACCURACY / _outputIndexed;
    }

    function validatePriceDeviation(
        address _indexToken, 
        uint _indexAmount, 
        uint _stableAmount,
        uint _referencePrice,
        bool _init
    ) internal view {
        _referencePrice = _init ? _referencePrice : getPrice(_indexToken);
        uint _newMarkPrice = _stableAmount * ACCURACY / _indexAmount;
        uint _maxPriceDelta = _referencePrice * allowedPriceDeviation / PRECISION;

        _newMarkPrice > _referencePrice ? 
        require(_referencePrice + _maxPriceDelta >= _newMarkPrice, "VAMM: max deviation overflow") : 
        require(_newMarkPrice >= _referencePrice - _maxPriceDelta, "VAMM: max deviation underflow");
    }

    function validateLiquidity(uint _indexAmount, uint _stableAmount) internal pure {
        require(_indexAmount * _stableAmount >= MIN_LIQUIDITY, "VAMM: invalid liquidity amount"); 
    }
}