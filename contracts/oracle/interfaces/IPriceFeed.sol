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
    function whitelistedToken(address _intexToken) external view returns(bool);

    function setTokenConfig(
        address _indexToken,
        address _priceFeed,
        uint _priceDecimals, 
        address _ammPool, 
        uint _poolDecimals
    ) external;

    function setPriceFeedAggregator(address _indexToken, address _priceFeed, uint _priceDecimals) external;

    function setAmmPool(address _indexToken, address _ammPool, uint _poolDecimals) external;

    function deleteTokenConfig(address _indexToken) external;

    function denyAmmPoolPrice(address _indexToken) external;

    function setIsFastPriceEnabled(bool _isFastPriceEnabled) external;

    function setIsAmmPriceEnabled(bool _isAmmPriceEnabled) external;

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;

    function setPriceSampleSpace(uint _priceSampleSpace) external;

    function setAmmPriceDuration(uint _ammPriceDuration) external;

    function getPrice(address _indexToken) external view returns(uint price);

    function getConfig(address _indexToken) external view returns(address, uint, address, uint);

    function getLatestPrimaryPrice(address _indexToken) external view returns(uint price);

    function getPrimaryPrice(address _indexToken) external view returns(uint price);

    function getFastPrice(address _indexToken, uint _referencePrice) external view returns(uint price);

    function getAmmPrice(address _indexToken) external view returns(uint price);

}