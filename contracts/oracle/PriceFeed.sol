// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IPriceAggregator.sol";
import "./interfaces/IFastPriceFeed.sol";
import "../libraries/Governable.sol";
import "../libraries/Math.sol";

contract PriceFeed is Governable, ReentrancyGuard {
    using Math for uint;

    uint public constant ACCURACY = 1e18;
    uint public constant PRECISION = 10000;
    uint public constant MAX_AMM_PRICE_DURATION = 1 hours;

    uint public priceSampleSpace;
    uint public ammPriceDuration;

    address public fastPriceFeed;

    bool public isFastPriceEnabled;
    bool public isAmmPriceEnabled;
    bool public favorPrimaryPrice;
    bool public isInitialized;
    
    mapping(address => bool) public whitelistedToken;
    mapping(address => Config) public configs;

    struct Config {
        address priceFeed;
        uint priceDecimals;
        address ammPool;
        uint poolDecimals;
    }

    modifier whitelisted(address _indexToken, bool _include) {
        require(whitelistedToken[_indexToken] == _include, "PriceFeed: invalid whitelisted");
        _;
    }

    function initialize(
        address _fastPriceFeed, 
        address _controller
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(!isInitialized, "PriceFeed: initialized");
        isInitialized = true;

        fastPriceFeed = _fastPriceFeed;
        controller = _controller;

        isFastPriceEnabled = true;
        isAmmPriceEnabled = false;
        favorPrimaryPrice = false;
        priceSampleSpace = 3;
        ammPriceDuration = 10 minutes;
    }

    function setTokenConfig(
        address _indexToken,
        address _priceFeed,
        uint _priceDecimals,
        address _ammPool,
        uint _poolDecimals
    ) external onlyHandler(controller) whitelisted(_indexToken, false) { 
        validatePoolAddress(_indexToken, _ammPool);
        configs[_indexToken] = Config({
            priceFeed: _priceFeed,
            priceDecimals: _priceDecimals,
            ammPool: _ammPool,
            poolDecimals: _poolDecimals
        });
        whitelistedToken[_indexToken] = true;
    }

    function setPriceFeedAggregator(
        address _indexToken, 
        address _priceFeed, 
        uint _priceDecimals
    ) external onlyHandler(controller) whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken]; 

        require(config.priceFeed == address(0), "PriceFeed: already set");
        config.priceFeed = _priceFeed;
        config.priceDecimals = _priceDecimals;
    }

    function setAmmPool(
        address _indexToken, 
        address _ammPool,
        uint _poolDecimals
    ) external onlyHandler(controller) whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken]; 

        validatePoolAddress(_indexToken, _ammPool);

        config.ammPool = _ammPool;
        config.poolDecimals = _poolDecimals;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {
        whitelistedToken[_indexToken] = false;
        delete configs[_indexToken];
    }

    function denyAmmPoolPrice(address _indexToken) external onlyHandler(fastPriceFeed) whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken]; 

        config.ammPool = address(0);
        config.poolDecimals = 0;
    }

    function setIsFastPriceEnabled(bool _isFastPriceEnabled) external onlyHandlers() {
        isFastPriceEnabled = _isFastPriceEnabled;
    }

    function setIsAmmPriceEnabled(bool _isAmmPriceEnabled) external onlyHandler(dao) {
        isAmmPriceEnabled = _isAmmPriceEnabled;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external onlyHandlers() {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(uint _priceSampleSpace) external onlyHandlers() {
        require(_priceSampleSpace > 0, "PriceFeed: invalid priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
    }

    function setAmmPriceDuration(uint _ammPriceDuration) external onlyHandlers() {
        require(MAX_AMM_PRICE_DURATION >= _ammPriceDuration, "PriceFeed: invalid ammPriceDuration");
        ammPriceDuration = _ammPriceDuration;
    }

    function getPrice(address _indexToken) external view returns(uint price) {
        price = getPrimaryPrice(_indexToken);

        if(favorPrimaryPrice && price > 0){
            return price;
        } else {
            if(isAmmPriceEnabled && price == 0) price = getAmmPrice(_indexToken);
            if(isFastPriceEnabled || price == 0) price = getFastPrice(_indexToken, price);
        }
        validatePrice(int(price));
    }

    function getConfig(address _indexToken) external view returns(address, uint, address, uint) {
        Config memory config = configs[_indexToken]; 
        return (config.priceFeed, config.priceDecimals, config.ammPool, config.poolDecimals);
    }

    function getLatestPrimaryPrice(address _indexToken) external view returns(uint) {
        Config memory config = configs[_indexToken];
        require(config.priceFeed != address(0), "PriceFeed: invalid price feed");

        int price = IPriceAggregator(config.priceFeed).latestAnswer();
        validatePrice(price);

        return uint(price);
    }

    function getPrimaryPrice(address _indexToken) public view returns(uint) {
        Config memory config = configs[_indexToken];
        if(config.priceFeed == address(0)) return 0;

        IPriceAggregator priceFeed = IPriceAggregator(config.priceFeed);

        uint _price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) { break; }
            uint p;

            if (i == 0) {
                int _p = priceFeed.latestAnswer();
                validatePrice(_p);
                p = uint(_p);
            } else {
                (, int _p, , ,) = priceFeed.getRoundData(roundId - i);
                validatePrice(_p);
                p = uint(_p);
            }

            if (_price == 0) {
                _price = p;
                continue;
            }
        }

        validatePrice(int(_price));
        return _price.mulDiv(ACCURACY, (10 ** config.priceDecimals));
    }

    function getFastPrice(address _indexToken, uint _referencePrice) public view returns(uint) {
        if(fastPriceFeed == address(0)) return _referencePrice;
        return IFastPriceFeed(fastPriceFeed).getPrice(_indexToken, _referencePrice);
    }

    function getAmmPrice(address _indexToken) public view returns(uint price) {
        Config memory config = configs[_indexToken]; 
        address _pool = config.ammPool;
        if(_pool == address(0)) return 0;

        (uint _reserve0, uint _reserve1, uint _blockTimestampLast) = IUniswapV2Pair(_pool).getReserves();
        
        if(block.timestamp >= _blockTimestampLast + ammPriceDuration) return 0;
        if(_reserve0 * _reserve1 == 0) return 0;

        price = _indexToken == IUniswapV2Pair(_pool).token0() ? 
        _reserve0.mulDiv(Math.ACCURACY, _reserve1) : 
        _reserve1.mulDiv(Math.ACCURACY, _reserve0);

        return price.mulDiv(ACCURACY, (10 ** config.poolDecimals));
    }

    function validatePoolAddress(address _indexToken, address _pool) internal view {
        if(_pool != address(0))
        require(
            _indexToken == IUniswapV2Pair(_pool).token0() || 
            _indexToken == IUniswapV2Pair(_pool).token1(), 
            "PriceFeed: invalid pool"
        );
    }

    function validatePrice(int _price) internal pure {
        require(_price > 0, "PriceFeed: invalid price");
    }
}