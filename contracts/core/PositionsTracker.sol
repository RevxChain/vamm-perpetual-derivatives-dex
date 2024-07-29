// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IVAMM.sol";

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

    modifier whitelisted(address token, bool include) {
        require(whitelistedToken[token] == include, "PositionsTracker: not whitelisted");
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
    ) external onlyHandler(gov) {  
        require(!isInitialized, "PositionsTracker: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        _setController(_controller);

        deltaDuration = 12 hours;
        liquidityDeviation = 1000;
    }

    function setUpdater(address updater, bool set) external onlyHandlers() {
        updaters[updater] = set;
    }

    function setDeltaDuration(uint newDeltaDuration) external onlyHandlers() {
        require(MAX_DELTA_DURATION >= newDeltaDuration, "PositionsTracker: invalid deltaDuration");
        deltaDuration = newDeltaDuration;
    }

    function setLiquidityDeviation(uint newLiquidityDeviation) external onlyHandlers() {
        require(MAX_LIQUIDITY_DEVIATION >= newLiquidityDeviation, "PositionsTracker: invalid liquidityDeviation");
        liquidityDeviation = newLiquidityDeviation;
    }

    function setTokenConfig(
        address indexToken,
        uint maxTotalLongSizes,
        uint maxTotalShortSizes
    ) external onlyHandler(controller) whitelisted(indexToken, false) {   
        Config storage config = configs[indexToken];
        whitelistedToken[indexToken] = true;
        config.maxTotalLongSizes = maxTotalLongSizes;
        config.maxTotalShortSizes = maxTotalShortSizes;
        whitelistedTokensCount += 1;
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {   
        whitelistedToken[indexToken] = false;
        whitelistedTokensCount -= 1;

        delete configs[indexToken];
    }

    function setMaxTotalSizes(
        address indexToken, 
        uint maxTotalLongSizes, 
        uint maxTotalShortSizes
    ) external onlyHandlers() whitelisted(indexToken, true) {
        Config storage config = configs[indexToken];
        require(maxTotalLongSizes > config.totalLongSizes, "PositionsTracker: actual long sizes exceeded");
        require(maxTotalShortSizes > config.totalShortSizes, "PositionsTracker: actual short sizes exceeded");
        config.maxTotalLongSizes = maxTotalLongSizes;
        config.maxTotalShortSizes = maxTotalShortSizes;
    }

    function increaseTotalSizes(
        address indexToken, 
        uint sizeDelta, 
        uint markPrice, 
        bool long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[indexToken];
        uint _assetsAmount = sizeDelta / markPrice;
        if(long){
            require(
                config.maxTotalLongSizes > config.totalLongSizes + sizeDelta, 
                "PositionsTracker: actual long sizes exceeded"
            );
            config.totalLongSizes += sizeDelta; 
            config.totalLongAssets += _assetsAmount;
        } else {
            require(
                config.maxTotalShortSizes > config.totalShortSizes + sizeDelta, 
                "PositionsTracker: actual short sizes exceeded"
            );
            config.totalShortSizes += sizeDelta;
            config.totalShortAssets += _assetsAmount;
        }
    }

    function decreaseTotalSizes(
        address indexToken, 
        uint sizeDelta, 
        uint markPrice, 
        bool long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[indexToken];
        uint _assetsAmount = sizeDelta / markPrice;
        if(long){
            config.totalLongSizes -= sizeDelta; 
            config.totalLongAssets > _assetsAmount ? config.totalLongAssets -= _assetsAmount : 0;
        } else {
            config.totalShortSizes -= sizeDelta;
            config.totalShortAssets > _assetsAmount ? config.totalShortAssets -= _assetsAmount : 0;
        }
    }

    function updateTotalPositionsProfit(address[] calldata indexTokens) external onlyUpdater() {
        require(indexTokens.length == whitelistedTokensCount, "PositionsTracker: invalid tokens array length");
        (hasTradersProfit, totalPositionsDelta) = calculateProfits(indexTokens);
        lastPoolAmount = IVault(vault).poolAmount();
        lastUpdatedTime = block.timestamp;
    } 

    function getPositionsData() external view returns(bool, bool, uint) {
        (bool _isActual, uint _poolAmount) = (true, IVault(vault).poolAmount());

        (, uint _delta) = calculateDelta(lastPoolAmount, _poolAmount);

        if(_delta > liquidityDeviation) _isActual = false;
        if(block.timestamp >= lastUpdatedTime + deltaDuration) _isActual = false;

        return (_isActual, hasTradersProfit, totalPositionsDelta);
    }

    function calculateProfits(address[] calldata indexTokens) internal view returns(bool hasProfit, uint delta) {
        uint _totalSizes;
        int _totalDelta;
        for(uint i; indexTokens.length > i; i++){
            (uint _size, int _delta) = calculateProfit(indexTokens[i]);
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
        address indexToken
    ) internal view whitelisted(indexToken, true) returns(uint totalSizes, int delta) {
        Config memory config = configs[indexToken];
        uint _markPrice = IVAMM(VAMM).getPrice(indexToken);
        
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

    function calculateDelta(uint num, uint refNum) internal pure returns(uint delta, uint pDelta) {
        delta = num > refNum ? num - refNum : refNum - num;
        if(delta == 0 || num == 0) return (0, 0);
        pDelta = delta.mulDiv(Math.PRECISION, num);
    }
}