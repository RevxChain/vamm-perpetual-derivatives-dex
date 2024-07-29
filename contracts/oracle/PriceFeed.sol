// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IPriceAggregator.sol";
import "./interfaces/IFastPriceFeed.sol";

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

    modifier whitelisted(address indexToken, bool include) {
        require(whitelistedToken[indexToken] == include, "PriceFeed: invalid whitelisted");
        _;
    }

    function initialize(
        address _fastPriceFeed, 
        address _controller
    ) external onlyHandler(gov) {  
        require(!isInitialized, "PriceFeed: initialized");
        isInitialized = true;

        fastPriceFeed = _fastPriceFeed;
        _setController(_controller);

        isFastPriceEnabled = true;
        isAmmPriceEnabled = false;
        favorPrimaryPrice = false;
        priceSampleSpace = 3;
        ammPriceDuration = 10 minutes;
    }

    function setTokenConfig(
        address indexToken,
        address priceFeed,
        uint priceDecimals,
        address ammPool,
        uint poolDecimals
    ) external onlyHandler(controller) whitelisted(indexToken, false) { 
        validatePoolAddress(indexToken, ammPool);
        configs[indexToken] = Config({
            priceFeed: priceFeed,
            priceDecimals: priceDecimals,
            ammPool: ammPool,
            poolDecimals: poolDecimals
        });
        whitelistedToken[indexToken] = true;
    }

    function setPriceFeedAggregator(
        address indexToken, 
        address priceFeed, 
        uint priceDecimals
    ) external onlyHandler(controller) whitelisted(indexToken, true) {
        Config storage config = configs[indexToken]; 

        require(config.priceFeed == address(0), "PriceFeed: already set");
        config.priceFeed = priceFeed;
        config.priceDecimals = priceDecimals;
    }

    function setAmmPool(
        address indexToken, 
        address ammPool,
        uint poolDecimals
    ) external onlyHandler(controller) whitelisted(indexToken, true) {
        Config storage config = configs[indexToken]; 

        validatePoolAddress(indexToken, ammPool);

        config.ammPool = ammPool;
        config.poolDecimals = poolDecimals;
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {
        whitelistedToken[indexToken] = false;
        delete configs[indexToken];
    }

    function denyAmmPoolPrice(address indexToken) external onlyHandler(fastPriceFeed) whitelisted(indexToken, true) {
        Config storage config = configs[indexToken]; 

        config.ammPool = address(0);
        config.poolDecimals = 0;
    }

    function setIsFastPriceEnabled(bool enableFastPrice) external onlyHandlers() {
        isFastPriceEnabled = enableFastPrice;
    }

    function setIsAmmPriceEnabled(bool enableAmmPrice) external onlyHandler(dao) {
        isAmmPriceEnabled = enableAmmPrice;
    }

    function setFavorPrimaryPrice(bool enableFavorPrimaryPrice) external onlyHandlers() {
        favorPrimaryPrice = enableFavorPrimaryPrice;
    }

    function setPriceSampleSpace(uint newPriceSampleSpace) external onlyHandlers() {
        require(newPriceSampleSpace > 0, "PriceFeed: invalid priceSampleSpace");
        priceSampleSpace = newPriceSampleSpace;
    }

    function setAmmPriceDuration(uint newAmmPriceDuration) external onlyHandlers() {
        require(MAX_AMM_PRICE_DURATION >= newAmmPriceDuration, "PriceFeed: invalid ammPriceDuration");
        ammPriceDuration = newAmmPriceDuration;
    }

    function getPrice(address indexToken) external view returns(uint price) {
        price = getPrimaryPrice(indexToken);

        if(favorPrimaryPrice && price > 0){
            return price;
        } else {
            if(isAmmPriceEnabled && price == 0) price = getAmmPrice(indexToken);
            if(isFastPriceEnabled || price == 0) price = getFastPrice(indexToken, price);
        }
        validatePrice(int(price));
    }

    function getConfig(address indexToken) external view returns(address, uint, address, uint) {
        Config memory config = configs[indexToken]; 
        return (config.priceFeed, config.priceDecimals, config.ammPool, config.poolDecimals);
    }

    function getLatestPrimaryPrice(address indexToken) external view returns(uint) {
        Config memory config = configs[indexToken];
        require(config.priceFeed != address(0), "PriceFeed: invalid price feed");

        int price = IPriceAggregator(config.priceFeed).latestAnswer();
        validatePrice(price);

        return uint(price);
    }

    function getPrimaryPrice(address indexToken) public view returns(uint) {
        Config memory config = configs[indexToken];
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

    function getFastPrice(address indexToken, uint referencePrice) public view returns(uint) {
        if(fastPriceFeed == address(0)) return referencePrice;
        return IFastPriceFeed(fastPriceFeed).getPrice(indexToken, referencePrice);
    }

    function getAmmPrice(address indexToken) public view returns(uint price) {
        Config memory config = configs[indexToken]; 
        address _pool = config.ammPool;
        if(_pool == address(0)) return 0;

        (uint _reserve0, uint _reserve1, uint _blockTimestampLast) = IUniswapV2Pair(_pool).getReserves();
        
        if(block.timestamp >= _blockTimestampLast + ammPriceDuration) return 0;
        if(_reserve0 * _reserve1 == 0) return 0;

        price = indexToken == IUniswapV2Pair(_pool).token0() ? 
        _reserve0.mulDiv(Math.ACCURACY, _reserve1) : 
        _reserve1.mulDiv(Math.ACCURACY, _reserve0);

        return price.mulDiv(ACCURACY, (10 ** config.poolDecimals));
    }

    function validatePoolAddress(address indexToken, address pool) internal view {
        if(pool != address(0))
        require(
            indexToken == IUniswapV2Pair(pool).token0() || 
            indexToken == IUniswapV2Pair(pool).token1(), 
            "PriceFeed: invalid pool"
        );
    }

    function validatePrice(int price) internal pure {
        require(price > 0, "PriceFeed: invalid price");
    }
}