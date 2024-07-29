// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IPositionsTracker.sol";
import "./interfaces/IVault.sol";

contract VAMM is Governable {
    using Math for uint; 

    uint public constant MIN_LIQUIDITY = 2e27;
    uint public constant MAX_ALLOWED_PRICE_DEVIATION = 100; 
    uint public constant MIN_LIQUIDITY_UPDATE_DELAY = 12 hours;

    uint public allowedPriceDeviation;

    address public vault;
    address public positionsTracker;

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
        require(routers[msg.sender], "VAMM: invalid handler");
        _;
    }

    modifier whitelisted(address indexToken, bool include) {
        require(whitelistedToken[indexToken] == include, "VAMM: invalid whitelisted");
        _;
    }

    function initialize(
        address _vault,
        address _positionsTracker,
        address _marketRouter,
        address _orderBook,
        address _controller
    ) external onlyHandler(gov) {  
        require(!isInitialized, "VAMM: initialized");
        isInitialized = true;

        vault = _vault;
        positionsTracker = _positionsTracker;
        _setController(_controller);
        routers[_marketRouter] = true;
        routers[_orderBook] = true;

        allowedPriceDeviation = 30;
    }

    function setAllowedPriceDeviation(uint newAllowedPriceDeviation) external onlyHandler(dao) {
        require(MAX_ALLOWED_PRICE_DEVIATION >= newAllowedPriceDeviation, "VAMM: price deviation exceeded");
        allowedPriceDeviation = newAllowedPriceDeviation;
    }

    function setTokenConfig(
        address indexToken,
        uint indexAmount,
        uint stableAmount,
        uint referencePrice
    ) external onlyHandler(controller) whitelisted(indexToken, false) {      
        validateLiquidity(indexAmount, stableAmount);
        validatePriceDeviation(indexToken, indexAmount, stableAmount, referencePrice, true);

        Pair storage pair = pairs[indexToken]; 
        pair.indexAmount = indexAmount;
        pair.stableAmount = stableAmount;
        pair.liquidity = indexAmount * stableAmount;
        pair.lastUpdateTime = block.timestamp;

        whitelistedToken[indexToken] = true;
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {   
        whitelistedToken[indexToken] = false;

        delete pairs[indexToken];
    }

    function updateIndex(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta,
        bool long,
        bool increase,
        bool liquidation,
        address feeReceiver
    ) external onlyRouter() whitelisted(indexToken, true) {   
        Pair storage pair = pairs[indexToken]; 

        uint _markPrice = getPrice(indexToken);

        if(sizeDelta > 0){
            uint _newStableAmount;
            uint _newIndexAmount;
            (_newStableAmount, _newIndexAmount, _markPrice) = preCalculatePrice(indexToken, sizeDelta, increase, long);

            pair.stableAmount = _newStableAmount;
            pair.indexAmount = _newIndexAmount;
        }

        if(increase){
            IVault(vault).increasePosition(
                user, 
                indexToken, 
                collateralDelta, 
                sizeDelta,
                long,
                _markPrice
            );

            IPositionsTracker(positionsTracker).increaseTotalSizes(indexToken, sizeDelta, _markPrice, long);
        } else {
            !liquidation ? 
            IVault(vault).decreasePosition(
                user, 
                indexToken, 
                collateralDelta, 
                sizeDelta,
                long,
                _markPrice
            ) :
            IVault(vault).liquidatePosition(
                user,  
                indexToken,
                sizeDelta,
                long, 
                feeReceiver
            );

            IPositionsTracker(positionsTracker).decreaseTotalSizes(indexToken, sizeDelta, _markPrice, long);
        } 
    }

    // test function
    function setPrice(
        address indexToken, 
        uint indexAmount,
        uint stableAmount
    ) external {
        Pair storage pair = pairs[indexToken]; 
        pair.indexAmount = indexAmount;
        pair.stableAmount = stableAmount;
        pair.liquidity = indexAmount * stableAmount;
    }

    function setLiquidity(
        address indexToken, 
        uint indexAmount, 
        uint stableAmount
    ) external onlyHandlers() whitelisted(indexToken, true) {
        validateLiquidity(indexAmount, stableAmount);
        Pair storage pair = pairs[indexToken]; 
        require(block.timestamp >= pair.lastUpdateTime + MIN_LIQUIDITY_UPDATE_DELAY, "VAMM: premature update");
        validatePriceDeviation(indexToken, indexAmount, stableAmount, 0, false);

        pair.indexAmount = indexAmount;
        pair.stableAmount = stableAmount;
        pair.liquidity = indexAmount * stableAmount;
        pair.lastUpdateTime = block.timestamp;
    }

    function getData(address indexToken) external view returns(uint, uint, uint, uint) {
        Pair memory pair = pairs[indexToken]; 
        return (pair.indexAmount, pair.stableAmount, pair.liquidity, pair.lastUpdateTime);
    }

    function getPrice(address indexToken) public view returns(uint) {
        return pairs[indexToken].stableAmount.mulDiv(Math.ACCURACY, pairs[indexToken].indexAmount);
    }

    function preCalculatePrice(
        address indexToken, 
        uint sizeDelta, 
        bool increase, 
        bool long
    ) public view returns(uint newStableAmount, uint newIndexAmount, uint markPrice) {
        uint _outputIndexed; 
        Pair memory pair = pairs[indexToken]; 

        if(increase && !long || !increase && long){
            newStableAmount = pair.stableAmount - sizeDelta;
            newIndexAmount = pair.liquidity / newStableAmount;
            _outputIndexed = newIndexAmount - pair.indexAmount;
        } else {
            newStableAmount = pair.stableAmount + sizeDelta;
            newIndexAmount = pair.liquidity / newStableAmount;
            _outputIndexed = pair.indexAmount - newIndexAmount;
        }

        markPrice = sizeDelta.mulDiv(Math.ACCURACY, _outputIndexed);
    }

    function validatePriceDeviation(
        address indexToken, 
        uint indexAmount, 
        uint stableAmount,
        uint referencePrice,
        bool init
    ) internal view {
        referencePrice = init ? referencePrice : getPrice(indexToken);
        uint _newMarkPrice = stableAmount.mulDiv(Math.ACCURACY, indexAmount);
        uint _maxPriceDelta = referencePrice.mulDiv(allowedPriceDeviation, Math.PRECISION);

        _newMarkPrice > referencePrice ? 
        require(referencePrice + _maxPriceDelta >= _newMarkPrice, "VAMM: max deviation overflow") : 
        require(_newMarkPrice >= referencePrice - _maxPriceDelta, "VAMM: max deviation underflow");
    }

    function validateLiquidity(uint indexAmount, uint stableAmount) internal pure {
        require(indexAmount * stableAmount >= MIN_LIQUIDITY, "VAMM: invalid liquidity amount"); 
    }
}