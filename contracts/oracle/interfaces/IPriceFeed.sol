// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPriceFeed {

    function priceSampleSpace() external view returns(uint);
    function ammPriceDuration() external view returns(uint);
    function fastPriceFeed() external view returns(address);
    function controller() external view returns(address);
    function isFastPriceEnabled() external view returns(bool);
    function isAmmPriceEnabled() external view returns(bool);
    function favorPrimaryPrice() external view returns(bool);
    function isInitialized() external view returns(bool);
    
    function whitelistedToken(address indexToken) external view returns(bool);
    function configs(address indexToken) external view returns(Config memory);
    
    struct Config {
        address priceFeed;
        uint priceDecimals;
        address ammPool;
        uint poolDecimals;
    }

    function setTokenConfig(
        address indexToken,
        address priceFeed,
        uint priceDecimals, 
        address ammPool, 
        uint poolDecimals
    ) external;

    function setPriceFeedAggregator(address indexToken, address priceFeed, uint priceDecimals) external;

    function setAmmPool(address indexToken, address ammPool, uint poolDecimals) external;

    function deleteTokenConfig(address indexToken) external;

    function denyAmmPoolPrice(address indexToken) external;

    function setIsFastPriceEnabled(bool enableFastPrice) external;

    function setIsAmmPriceEnabled(bool enableAmmPrice) external;

    function setFavorPrimaryPrice(bool enableFavorPrimaryPrice) external;

    function setPriceSampleSpace(uint newPriceSampleSpace) external;

    function setAmmPriceDuration(uint newAmmPriceDuration) external;

    function getPrice(address indexToken) external view returns(uint price);

    function getConfig(address indexToken) external view returns(address priceFeed, uint priceDecimals, address ammPool, uint poolDecimals);

    function getLatestPrimaryPrice(address indexToken) external view returns(uint price);

    function getPrimaryPrice(address indexToken) external view returns(uint price);

    function getFastPrice(address indexToken, uint referencePrice) external view returns(uint price);

    function getAmmPrice(address indexToken) external view returns(uint price);

}