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

    function watchers(address watcher) external view returns(bool);
    function whitelistedToken(address indexToken) external view returns(bool);
    function priceDenied(address indexToken, address watcher) external view returns(bool);

    function setWatcher(address watcher) external;

    function deleteWatcher(address watcher) external;

    function setProvider(address providerAddress) external;

    function deleteProvider(address providerAddress) external;

    function discardDenials(address indexToken) external;

    function blockProvider(address providerAddress) external;

    function denyPrice(address indexToken) external;

    function cancelDenyPrice(address indexToken) external;

    function denyAmmPoolPrice(address indexToken) external;

    function setMaxTimeDeviation(uint newMaxTimeDeviation) external;

    function setPriceDuration(uint newPriceDuration) external;

    function setMinBlockInterval(uint newMinBlockInterval) external;

    function setLastUpdatedAt(uint newLastUpdatedAt) external;
    
    function setLastUpdatedBlock(uint newLastUpdatedBlock) external;

    function setPriceDataInterval(uint newPriceDataInterval) external;

    function setMaxDelta(address indexToken, uint maxDelta) external;

    function setMaxCumulativeDelta(address indexToken, uint maxCumulativeDelta) external;

    function setTokenConfig(address indexToken, uint price, uint refPrice, uint maxDelta, uint maxCumulativeDelta) external;

    function deleteTokenConfig(address indexToken) external;

    function setPrices(address[] memory indexTokens, uint[] memory prices, uint timestamp) external;

    function getPrice(address indexToken, uint refPrice) external view returns(uint);
   
}