// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/Governable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVAMM.sol";
import "../libraries/Math.sol";

contract PositionsTracker is Governable, ReentrancyGuard {
    using Math for uint;

    uint public constant MAX_DELTA_DURATION = 1 days;
    uint public constant MAX_LIQUIDITY_DEVIATION = 2000;

    uint public whitelistedTokensCount;
    uint public totalPositionsDelta; 
    uint public lastUpdatedTime;
    uint public deltaDuration;
    uint public lastPoolAmount;
    uint public liquidityDeviation;

    address public vault;
    address public VAMM;
    address public stable;
    
    bool public hasTradersProfit;
    bool public isInitialized;

    mapping(address => bool) public whitelistedToken;
    mapping(address => Config) public configs;
    mapping(address => bool) public updaters;

    struct Config {
        uint totalLongSizes;
        uint totalShortSizes;
        uint totalLongAssets;
        uint totalShortAssets;
        uint maxTotalLongSizes;
        uint maxTotalShortSizes;
    }

    modifier whitelisted(address _token, bool _include) {
        require(whitelistedToken[_token] == _include, "PositionsTracker: not whitelisted");
        _;
    }

    modifier onlyUpdater() {
        require(updaters[msg.sender], "PositionsTracker: invalid handler");
        _;
    }

    function initialize(
        address _vault,
        address _VAMM,
        address _controller
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(!isInitialized, "PositionsTracker: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        controller = _controller;

        deltaDuration = 12 hours;
        liquidityDeviation = 1000;
    }

    function setUpdater(address _updater, bool _bool) external onlyHandlers() {
        updaters[_updater] = _bool;
    }

    function setDeltaDuration(uint _deltaDuration) external onlyHandlers() {
        require(MAX_DELTA_DURATION >= _deltaDuration, "PositionsTracker: invalid deltaDuration");
        deltaDuration = _deltaDuration;
    }

    function setLiquidityDeviation(uint _liquidityDeviation) external onlyHandlers() {
        require(MAX_LIQUIDITY_DEVIATION >= _liquidityDeviation, "PositionsTracker: invalid liquidityDeviation");
        liquidityDeviation = _liquidityDeviation;
    }

    function setTokenConfig(
        address _indexToken,
        uint _maxTotalLongSizes,
        uint _maxTotalShortSizes
    ) external onlyHandler(controller) whitelisted(_indexToken, false) {   
        Config storage config = configs[_indexToken];
        whitelistedToken[_indexToken] = true;
        config.maxTotalLongSizes = _maxTotalLongSizes;
        config.maxTotalShortSizes = _maxTotalShortSizes;
        whitelistedTokensCount += 1;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {   
        whitelistedToken[_indexToken] = false;
        whitelistedTokensCount -= 1;

        delete configs[_indexToken];
    }

    function setMaxTotalSizes(
        address _indexToken, 
        uint _maxTotalLongSizes, 
        uint _maxTotalShortSizes
    ) external onlyHandlers() whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken];
        require(_maxTotalLongSizes > config.totalLongSizes, "PositionsTracker: actual long sizes exceeded");
        require(_maxTotalShortSizes > config.totalShortSizes, "PositionsTracker: actual short sizes exceeded");
        config.maxTotalLongSizes = _maxTotalLongSizes;
        config.maxTotalShortSizes = _maxTotalShortSizes;
    }

    function increaseTotalSizes(
        address _indexToken, 
        uint _sizeDelta, 
        uint _markPrice, 
        bool _long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[_indexToken];
        uint _assetsAmount = _sizeDelta / _markPrice;
        if(_long){
            require(
                config.maxTotalLongSizes > config.totalLongSizes + _sizeDelta, 
                "PositionsTracker: actual long sizes exceeded"
            );
            config.totalLongSizes += _sizeDelta; 
            config.totalLongAssets += _assetsAmount;
        } else {
            require(
                config.maxTotalShortSizes > config.totalShortSizes + _sizeDelta, 
                "PositionsTracker: actual short sizes exceeded"
            );
            config.totalShortSizes += _sizeDelta;
            config.totalShortAssets += _assetsAmount;
        }
    }

    function decreaseTotalSizes(
        address _indexToken, 
        uint _sizeDelta, 
        uint _markPrice, 
        bool _long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[_indexToken];
        uint _assetsAmount = _sizeDelta / _markPrice;
        if(_long){
            config.totalLongSizes -= _sizeDelta; 
            config.totalLongAssets > _assetsAmount ? config.totalLongAssets -= _assetsAmount : 0;
        } else {
            config.totalShortSizes -= _sizeDelta;
            config.totalShortAssets > _assetsAmount ? config.totalShortAssets -= _assetsAmount : 0;
        }
    }

    function updateTotalPositionsProfit(address[] calldata _indexTokens) external onlyUpdater() {
        require(_indexTokens.length == whitelistedTokensCount, "PositionsTracker: invalid tokens array length");
        (hasTradersProfit, totalPositionsDelta) = calculateProfits(_indexTokens);
        lastPoolAmount = IVault(vault).poolAmount();
        lastUpdatedTime = block.timestamp;
    } 

    function getPositionsData() external view returns(bool, bool, uint) {
        bool _isActual = true;
        uint _poolAmount = IVault(vault).poolAmount();

        (, uint _delta) = calculateDelta(lastPoolAmount, _poolAmount);

        if(_delta > liquidityDeviation) _isActual = false;
        if(block.timestamp >= lastUpdatedTime + deltaDuration) _isActual = false;

        return (_isActual, hasTradersProfit, totalPositionsDelta);
    }

    function calculateProfits(address[] calldata _indexTokens) internal view returns(bool hasProfit, uint delta) {
        uint _totalSizes;
        int _totalDelta;
        for(uint i; _indexTokens.length > i; i++){
            (uint _size, int _delta) = calculateProfit(_indexTokens[i]);
            _totalSizes += _size;
            _totalDelta += _delta;
        }

        if(_totalDelta > 0){
            hasProfit = true;    
        } else {
            _totalDelta = -_totalDelta;
        }
        
        delta = uint(_totalDelta).mulDiv(Math.PRECISION, _totalSizes);
    }

    function calculateProfit(
        address _indexToken
    ) internal view whitelisted(_indexToken, true) returns(uint totalSizes, int delta) {
        Config memory config = configs[_indexToken];
        uint _markPrice = IVAMM(VAMM).getPrice(_indexToken);
        
        if(config.totalLongAssets > 0){
            uint _longAveragePrice = config.totalLongSizes / config.totalLongAssets;
            (uint _longPriceDelta, ) = calculateDelta(_markPrice, _longAveragePrice);
            int _longProfit = int(_longPriceDelta * config.totalLongAssets);
            if(_longAveragePrice > _markPrice) _longProfit = -_longProfit;
            totalSizes += config.totalLongSizes;
            delta += _longProfit;
        }
        if(config.totalShortAssets > 0){
            uint _shortAveragePrice = config.totalShortSizes / config.totalShortAssets;
            (uint _shortPriceDelta, ) = calculateDelta(_markPrice, _shortAveragePrice);
            int _shortProfit = int(_shortPriceDelta * config.totalShortAssets);
            if(_markPrice > _shortAveragePrice) _shortProfit = -_shortProfit;
            totalSizes += config.totalShortSizes;
            delta += _shortProfit;
        } 
    }

    function calculateDelta(uint _num, uint _refNum) internal pure returns(uint delta, uint pDelta) {
        delta = _num > _refNum ? _num - _refNum : _refNum - _num;
        pDelta = delta.mulDiv(Math.PRECISION, _num);
    }
}