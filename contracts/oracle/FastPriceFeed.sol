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

    modifier whitelisted(address _indexToken, bool _include) {
        require(whitelistedToken[_indexToken] == _include, "FastPriceFeed: invalid whitelisted");
        _;
    }

    modifier validateToken(address _indexToken) {
        require(whitelistedToken[_indexToken] || _indexToken == address(0), "FastPriceFeed: invalid token");
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

    function setWatcher(address _watcher) external onlyHandlers() {
        require(!watchers[_watcher], "FastPriceFeed: watcher already");
        watchers[_watcher] = true;
        watchersCount += 1;
    }

    function deleteWatcher(address _watcher) external onlyHandlers() {
        require(watchers[_watcher], "FastPriceFeed: is not watcher");
        watchers[_watcher] = false;
        watchersCount -= 1;
    }

    function setProvider(address _provider) external onlyHandler(dao) {
        Provider storage provider = providers[_provider]; 
        require(!provider.updater, "FastPriceFeed: provider is updater");
        require(!provider.banned, "FastPriceFeed: provider banned");
        provider.updater = true;
    }

    function deleteProvider(address _provider) external onlyHandlers() {
        Provider storage provider = providers[_provider]; 
        require(provider.updater, "FastPriceFeed: provider is not updater");
        provider.updater = false;
    }

    function discardDenials(address _indexToken) external onlyHandler(dao) validateToken(_indexToken) {
        _indexToken == address(0) ? globalDenials = 0 : priceData[_indexToken].denials = 0;
    }

    function blockProvider(address _provider) external onlyWatcher() {
        Provider storage provider = providers[_provider]; 
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

    function denyPrice(address _indexToken) external onlyWatcher() validateToken(_indexToken) {
        require(!priceDenied[_indexToken][msg.sender], "FastPriceFeed: denied already");
        priceDenied[_indexToken][msg.sender] = true;
        _indexToken == address(0) ? globalDenials += 1 : priceData[_indexToken].denials += 1;
    }

    function cancelDenyPrice(address _indexToken) external onlyWatcher() validateToken(_indexToken) {
        require(priceDenied[_indexToken][msg.sender], "FastPriceFeed: cancelled already");
        priceDenied[_indexToken][msg.sender] = false;
        _indexToken == address(0) ? globalDenials -= 1 : priceData[_indexToken].denials -= 1;
    }

    function denyAmmPoolPrice(address _indexToken) external onlyProvider() whitelisted(_indexToken, true) {
        IPriceFeed(priceFeed).denyAmmPoolPrice(_indexToken);
    }

    function setMaxTimeDeviation(uint _maxTimeDeviation) external onlyHandlers() {
        maxTimeDeviation = _maxTimeDeviation;
    }

    function setPriceDuration(uint _priceDuration) external onlyHandlers() {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid priceDuration");
        priceDuration = _priceDuration;
    }

    function setMinBlockInterval(uint _minBlockInterval) external onlyHandlers() {
        minBlockInterval = _minBlockInterval;
    }

    function setLastUpdatedAt(uint _lastUpdatedAt) external onlyHandler(dao) {
        lastUpdatedAt = _lastUpdatedAt;
    }
    
    function setLastUpdatedBlock(uint _lastUpdatedBlock) external onlyHandler(dao) {
        lastUpdatedBlock = _lastUpdatedBlock;
    } 

    function setPriceDataInterval(uint _priceDataInterval) external onlyHandler(dao) {
        require(_priceDataInterval <= MAX_PRICE_DATA_INTERVAL, "FastPriceFeed: invalid priceDataInterval");
        priceDataInterval = _priceDataInterval;
    }

    function setMaxDelta(
        address _indexToken, 
        uint _maxDelta
    ) external onlyHandler(dao) whitelisted(_indexToken, true) {
        PriceData storage data = priceData[_indexToken]; 
        validateDelta(_maxDelta, data.delta, 0, 0);
        data.maxDelta = _maxDelta;
    }

    function setMaxCumulativeDelta(
        address _indexToken, 
        uint _maxCumulativeDelta
    ) external onlyHandler(dao) whitelisted(_indexToken, true) {
        PriceData storage data = priceData[_indexToken]; 
        validateDelta(0, 0, _maxCumulativeDelta, data.cumulativeDelta);
        data.cumulativeDelta = _maxCumulativeDelta;
    }

    function setTokenConfig(
        address _indexToken,
        uint _price,
        uint _refPrice,
        uint _maxDelta,
        uint _maxCumulativeDelta
    ) external onlyHandler(controller) whitelisted(_indexToken, false) { 
        whitelistedToken[_indexToken] = true;
        require(_price > 0 && _refPrice > 0, "FastPriceFeed: invalid price");
        uint _delta = calculateDelta(_price, _refPrice);

        validateDelta(_maxDelta, _delta, _maxCumulativeDelta, _delta);
        whitelistedTokensCount += 1; 

        priceData[_indexToken] = PriceData({
            price: _price,
            prevPrice: _price,
            refPrice: _refPrice,
            prevRefPrice: _refPrice,
            delta: _delta,
            maxDelta: _maxDelta,
            cumulativeDelta: _delta,
            maxCumulativeDelta: _maxCumulativeDelta,
            lastUpdate: block.timestamp,
            denials: 0
        });
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {
        whitelistedToken[_indexToken] = false;
        whitelistedTokensCount -= 1;
        delete priceData[_indexToken];
    }

    function setPrices(
        address[] memory _indexTokens, 
        uint[] memory _prices, 
        uint _timestamp
    ) external onlyProvider() {
        require(_indexTokens.length == whitelistedTokensCount, "FastPriceFeed: invalid tokens array length");
        bool shouldUpdate = shouldUpdatePrices(_timestamp);

        if(shouldUpdate){
            for (uint i = 0; i < _indexTokens.length; i++) {
                setPrice(_indexTokens[i], _prices[i]);
            }
        }
    }

    function getPrice(address _indexToken, uint _refPrice) external view returns(uint) {
        PriceData memory data = priceData[_indexToken]; 
        uint _price = data.price;
        if(!whitelistedToken[_indexToken]) return _refPrice;
        if(_price == 0) return _refPrice;
        if(_refPrice > 0){
            if(block.timestamp > data.lastUpdate + priceDuration) return _refPrice;
            if(data.cumulativeDelta > data.maxCumulativeDelta) return _refPrice;
            if(data.delta > data.maxDelta) return _refPrice;
        }

        int _denials = data.denials > globalDenials ? data.denials : globalDenials;
        int _watchers = int(watchersCount);
        if(1 >= _watchers){
            if(_denials >= _watchers / 2 + 1) return _refPrice;
        } else {
            if(_denials >= _watchers / 2) return _refPrice;
        }
        
        return _price;
    }

    function setPrice(address _indexToken, uint _price) internal whitelisted(_indexToken, true) { 
        PriceData storage data = priceData[_indexToken]; 
        uint _refPrice = IPriceFeed(priceFeed).getPrimaryPrice(_indexToken);
        uint _delta;

        if(data.lastUpdate / priceDataInterval != block.timestamp / priceDataInterval) data.cumulativeDelta = 0;

        if(_refPrice > 0){
            _delta = calculateDelta(_price, _refPrice);
            data.prevRefPrice = data.refPrice;
            data.refPrice = _refPrice;
        } else {
            _delta = calculateDelta(_price, data.price);
        }

        data.delta = _delta;
        data.cumulativeDelta += _delta;
        data.prevPrice = data.price;
        data.price = _price;
        data.lastUpdate = block.timestamp;
    }

    function shouldUpdatePrices(uint _timestamp) internal returns(bool) {
        if(minBlockInterval > 0) if(minBlockInterval > (block.number - lastUpdatedBlock)) return false;
        if(block.timestamp - maxTimeDeviation >= _timestamp) return false;
        if(_timestamp >= block.timestamp + maxTimeDeviation) return false;
        if(_timestamp < lastUpdatedAt) return false;

        lastUpdatedAt = _timestamp;
        lastUpdatedBlock = block.number;

        return true;
    }

    function validateDelta(uint _delta, uint _refDelta, uint _cumulativeDelta, uint _refCumulativeDelta) internal pure {
        require(
            _delta >= MIN_MAX_DELTA &&
            MAX_MAX_DELTA >= _delta &&
            _delta >= _refDelta, 
            "FastPriceFeed: invalid delta"
        );

        require(
            _cumulativeDelta >= MIN_MAX_CUMULATIVE_DELTA &&
            MAX_MAX_CUMULATIVE_DELTA >= _cumulativeDelta &&
            _cumulativeDelta >= _refCumulativeDelta, 
            "FastPriceFeed: invalid cumulativeDelta"
        );
    }

    function calculateDelta(uint _price, uint _refPrice) internal pure returns(uint delta) {
        delta = _price > _refPrice ? _price - _refPrice : _refPrice - _price;
        delta = delta * PRECISION / _price;
    }
}