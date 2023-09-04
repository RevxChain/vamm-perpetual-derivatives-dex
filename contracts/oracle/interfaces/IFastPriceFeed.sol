// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFastPriceFeed {

    function whitelistedTokensCount() external view returns(uint);
    function priceDuration() external view returns(uint);
    function watchersCount() external view returns(uint);
    function minBlockInterval() external view returns(uint);
    function priceDataInterval() external view returns(uint);
    function lastUpdatedAt() external view returns(uint);
    function lastUpdatedBlock() external view returns(uint);
    function maxTimeDeviation() external view returns(uint);
    function globalDenials() external view returns(int);
    function priceFeed() external view returns(address);

    function watchers(address _watcher) external view returns(bool);
    function whitelistedToken(address _indexToken) external view returns(bool);
    function priceDenied(address _indexToken, address _watcher) external view returns(bool);

    function setWatcher(address _watcher) external;

    function deleteWatcher(address _watcher) external;

    function setProvider(address _provider) external;

    function deleteProvider(address _provider) external;

    function discardDenials(address _indexToken) external;

    function blockProvider(address _provider) external;

    function denyPrice(address _indexToken) external;

    function cancelDenyPrice(address _indexToken) external;

    function denyAmmPoolPrice(address _indexToken) external;

    function setMaxTimeDeviation(uint _maxTimeDeviation) external;

    function setPriceDuration(uint _priceDuration) external;

    function setMinBlockInterval(uint _minBlockInterval) external;

    function setLastUpdatedAt(uint _lastUpdatedAt) external;
    
    function setLastUpdatedBlock(uint _lastUpdatedBlock) external;

    function setPriceDataInterval(uint _priceDataInterval) external;

    function setMaxDelta(address _indexToken, uint _maxDelta) external;

    function setMaxCumulativeDelta(address _indexToken, uint _maxCumulativeDelta) external;

    function setTokenConfig(address _indexToken, uint _price, uint _refPrice, uint _maxDelta, uint _maxCumulativeDelta) external;

    function deleteTokenConfig(address _indexToken) external;

    function setPrices(address[] memory _indexTokens, uint[] memory _prices, uint _timestamp) external;

    function getPrice(address _indexToken, uint _refPrice) external view returns(uint);
   
}