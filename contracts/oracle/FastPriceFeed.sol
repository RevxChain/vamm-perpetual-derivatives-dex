// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/Governable.sol";

import "./interfaces/IPriceFeed.sol";

contract FastPriceFeed is Governable {
    
    uint public constant ACCURACY = 1e18;
    uint public constant PRECISION = 10000;

    uint public constant MIN_MAX_DELTA = 100;
    uint public constant MAX_MAX_DELTA = 300;
    uint public constant MIN_MAX_CUMULATIVE_DELTA = 100;
    uint public constant MAX_MAX_CUMULATIVE_DELTA = 1500;
    uint public constant MIN_PRICE_DURATION = 3 minutes;
    uint public constant MAX_PRICE_DURATION = 30 minutes;
    uint public constant MAX_PRICE_DATA_INTERVAL = 60 minutes;
    
    uint public whitelistedTokensCount;
    uint public priceDuration;
    uint public watchersCount;
    uint public minBlockInterval;
    uint public priceDataInterval;
    uint public lastUpdatedAt;
    uint public lastUpdatedBlock;
    uint public maxTimeDeviation;

    int public globalDenials;

    address public priceFeed;

    bool public isInitialized;

    mapping(address => bool) public watchers;
    mapping(address => bool) public whitelistedToken;
    mapping(address => mapping(address => bool)) public priceDenied;
    mapping(address => PriceData) public priceData;
    mapping(address => Provider) providers;

    struct PriceData {
        uint price;
        uint prevPrice;
        uint refPrice;
        uint prevRefPrice;
        uint delta;
        uint maxDelta;
        uint cumulativeDelta;
        uint maxCumulativeDelta;
        uint lastUpdate;
        int denials;
    }

    struct Provider {
        bool updater;
        bool banned;
        uint denials;
        mapping(address => bool) blocked;
    }

    modifier whitelisted(address indexToken, bool include) {
        require(whitelistedToken[indexToken] == include, "FastPriceFeed: invalid whitelisted");
        _;
    }

    modifier validateToken(address indexToken) {
        require(whitelistedToken[indexToken] || indexToken == address(0), "FastPriceFeed: invalid token");
        _;
    }

    modifier onlyWatcher() {
        require(watchers[msg.sender], "FastPriceFeed: invalid handler");
        _;
    }

    modifier onlyProvider() {
        require(providers[msg.sender].updater, "FastPriceFeed: invalid handler");
        require(!providers[msg.sender].banned, "FastPriceFeed: banned handler");
        _;
    }

    function initialize(
        address _controller,
        address _priceFeed
    ) external onlyHandler(gov) validateAddress(_controller) {
        require(!isInitialized, "FastPriceFeed: initialized");
        isInitialized = true;

        controller = _controller;
        priceFeed = _priceFeed;

        priceDuration = 10 minutes;
        minBlockInterval = 0;
        maxTimeDeviation = 5 minutes;
        priceDataInterval = 30 minutes;
    }

    function setWatcher(address watcher) external onlyHandlers() {
        require(!watchers[watcher], "FastPriceFeed: watcher already");
        watchers[watcher] = true;
        watchersCount += 1;
    }

    function deleteWatcher(address watcher) external onlyHandlers() {
        require(watchers[watcher], "FastPriceFeed: is not watcher");
        watchers[watcher] = false;
        watchersCount -= 1;
    }

    function setProvider(address providerAddress) external onlyHandler(dao) {
        Provider storage provider = providers[providerAddress]; 
        require(!provider.updater, "FastPriceFeed: provider is updater");
        require(!provider.banned, "FastPriceFeed: provider banned");
        provider.updater = true;
    }

    function deleteProvider(address providerAddress) external onlyHandlers() {
        Provider storage provider = providers[providerAddress]; 
        require(provider.updater, "FastPriceFeed: provider is not updater");
        provider.updater = false;
    }

    function discardDenials(address indexToken) external onlyHandler(dao) validateToken(indexToken) {
        indexToken == address(0) ? globalDenials = 0 : priceData[indexToken].denials = 0;
    }

    function blockProvider(address providerAddress) external onlyWatcher() {
        Provider storage provider = providers[providerAddress]; 
        require(!provider.blocked[msg.sender], "FastPriceFeed: blocked already");
        require(provider.updater, "FastPriceFeed: provider is not updater");
        require(!provider.banned, "FastPriceFeed: banned already");
        provider.blocked[msg.sender] = true;
        provider.denials += 1;

        if(provider.denials > 2){
            provider.updater = false;
            provider.banned = true;
        }
    }

    function denyPrice(address indexToken) external onlyWatcher() validateToken(indexToken) {
        require(!priceDenied[indexToken][msg.sender], "FastPriceFeed: denied already");
        priceDenied[indexToken][msg.sender] = true;
        indexToken == address(0) ? globalDenials += 1 : priceData[indexToken].denials += 1;
    }

    function cancelDenyPrice(address indexToken) external onlyWatcher() validateToken(indexToken) {
        require(priceDenied[indexToken][msg.sender], "FastPriceFeed: cancelled already");
        priceDenied[indexToken][msg.sender] = false;
        indexToken == address(0) ? globalDenials -= 1 : priceData[indexToken].denials -= 1;
    }

    function denyAmmPoolPrice(address indexToken) external onlyProvider() whitelisted(indexToken, true) {
        IPriceFeed(priceFeed).denyAmmPoolPrice(indexToken);
    }

    function setMaxTimeDeviation(uint newMaxTimeDeviation) external onlyHandlers() {
        maxTimeDeviation = newMaxTimeDeviation;
    }

    function setPriceDuration(uint newPriceDuration) external onlyHandlers() {
        require(newPriceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid priceDuration");
        priceDuration = newPriceDuration;
    }

    function setMinBlockInterval(uint newMinBlockInterval) external onlyHandlers() {
        minBlockInterval = newMinBlockInterval;
    }

    function setLastUpdatedAt(uint newLastUpdatedAt) external onlyHandler(dao) {
        lastUpdatedAt = newLastUpdatedAt;
    }
    
    function setLastUpdatedBlock(uint newLastUpdatedBlock) external onlyHandler(dao) {
        lastUpdatedBlock = newLastUpdatedBlock;
    } 

    function setPriceDataInterval(uint newPriceDataInterval) external onlyHandler(dao) {
        require(newPriceDataInterval <= MAX_PRICE_DATA_INTERVAL, "FastPriceFeed: invalid priceDataInterval");
        priceDataInterval = newPriceDataInterval;
    }

    function setMaxDelta(
        address indexToken, 
        uint maxDelta
    ) external onlyHandler(dao) whitelisted(indexToken, true) {
        PriceData storage data = priceData[indexToken]; 
        validateDelta(maxDelta, data.delta, 0, 0);
        data.maxDelta = maxDelta;
    }

    function setMaxCumulativeDelta(
        address indexToken, 
        uint maxCumulativeDelta
    ) external onlyHandler(dao) whitelisted(indexToken, true) {
        PriceData storage data = priceData[indexToken]; 
        validateDelta(0, 0, maxCumulativeDelta, data.cumulativeDelta);
        data.cumulativeDelta = maxCumulativeDelta;
    }

    function setTokenConfig(
        address indexToken,
        uint price,
        uint refPrice,
        uint maxDelta,
        uint maxCumulativeDelta
    ) external onlyHandler(controller) whitelisted(indexToken, false) { 
        whitelistedToken[indexToken] = true;
        require(price > 0 && refPrice > 0, "FastPriceFeed: invalid price");
        uint _delta = calculateDelta(price, refPrice);

        validateDelta(maxDelta, _delta, maxCumulativeDelta, _delta);
        whitelistedTokensCount += 1; 

        priceData[indexToken] = PriceData({
            price: price,
            prevPrice: price,
            refPrice: refPrice,
            prevRefPrice: refPrice,
            delta: _delta,
            maxDelta: maxDelta,
            cumulativeDelta: _delta,
            maxCumulativeDelta: maxCumulativeDelta,
            lastUpdate: block.timestamp,
            denials: 0
        });
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {
        whitelistedToken[indexToken] = false;
        whitelistedTokensCount -= 1;
        delete priceData[indexToken];
    }

    function setPrices(
        address[] memory indexTokens, 
        uint[] memory prices, 
        uint timestamp
    ) external onlyProvider() {
        require(indexTokens.length == whitelistedTokensCount, "FastPriceFeed: invalid tokens array length");
        bool shouldUpdate = shouldUpdatePrices(timestamp);

        if(shouldUpdate) for(uint i = 0; i < indexTokens.length; i++) setPrice(indexTokens[i], prices[i]);
    }

    function getPrice(address indexToken, uint refPrice) external view returns(uint) {
        PriceData memory data = priceData[indexToken]; 
        uint _price = data.price;
        if(!whitelistedToken[indexToken]) return refPrice;
        if(_price == 0) return refPrice;
        if(refPrice > 0){
            if(block.timestamp > data.lastUpdate + priceDuration) return refPrice;
            if(data.cumulativeDelta > data.maxCumulativeDelta) return refPrice;
            if(data.delta > data.maxDelta) return refPrice;
        }

        int _denials = data.denials > globalDenials ? data.denials : globalDenials;
        int _watchers = int(watchersCount);
        if(1 >= _watchers){
            if(_denials >= _watchers / 2 + 1) return refPrice;
        } else {
            if(_denials >= _watchers / 2) return refPrice;
        }
        
        return _price;
    }

    function setPrice(address indexToken, uint price) internal whitelisted(indexToken, true) { 
        PriceData storage data = priceData[indexToken]; 
        uint _refPrice = IPriceFeed(priceFeed).getPrimaryPrice(indexToken);
        uint _delta;

        if(data.lastUpdate / priceDataInterval != block.timestamp / priceDataInterval) data.cumulativeDelta = 0;

        if(_refPrice > 0){
            _delta = calculateDelta(price, _refPrice);
            data.prevRefPrice = data.refPrice;
            data.refPrice = _refPrice;
        } else {
            _delta = calculateDelta(price, data.price);
        }

        data.delta = _delta;
        data.cumulativeDelta += _delta;
        data.prevPrice = data.price;
        data.price = price;
        data.lastUpdate = block.timestamp;
    }

    function shouldUpdatePrices(uint timestamp) internal returns(bool) {
        if(minBlockInterval > 0) if(minBlockInterval > (block.number - lastUpdatedBlock)) return false;
        if(block.timestamp - maxTimeDeviation >= timestamp) return false;
        if(timestamp >= block.timestamp + maxTimeDeviation) return false;
        if(timestamp < lastUpdatedAt) return false;

        lastUpdatedAt = timestamp;
        lastUpdatedBlock = block.number;

        return true;
    }

    function validateDelta(uint delta, uint refDelta, uint cumulativeDelta, uint refCumulativeDelta) internal pure {
        require(
            delta >= MIN_MAX_DELTA &&
            MAX_MAX_DELTA >= delta &&
            delta >= refDelta, 
            "FastPriceFeed: invalid delta"
        );

        require(
            cumulativeDelta >= MIN_MAX_CUMULATIVE_DELTA &&
            MAX_MAX_CUMULATIVE_DELTA >= cumulativeDelta &&
            cumulativeDelta >= refCumulativeDelta, 
            "FastPriceFeed: invalid cumulativeDelta"
        );
    }

    function calculateDelta(uint price, uint refPrice) internal pure returns(uint delta) {
        delta = price > refPrice ? price - refPrice : refPrice - price;
        delta = delta * PRECISION / price;
    }
}