// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPriceFeed {

    function priceSampleSpace() external view returns(uint);
    function fastPriceFeed() external view returns(address);
    function controller() external view returns(address);
    function isFastPriceEnabled() external view returns(bool);
    function favorPrimaryPrice() external view returns(bool);
    function isInitialized() external view returns(bool);
    function whitelistedToken(address _intexToken) external view returns(bool);

    function setTokenConfig(address _indexToken,address _priceFeed,uint _priceDecimals) external;

    function setPriceFeedAggregator(address _indexToken, address _priceFeed, uint _priceDecimals) external;

    function deleteTokenConfig(address _indexToken) external;

    function setIsFastPriceEnabled(bool _isFastPriceEnabled) external;

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;

    function setPriceSampleSpace(uint _priceSampleSpace) external;

    function getPrice(address _indexToken) external view returns(uint price);

    function getConfig(address _indexToken) external view returns(address, uint);

    function getLatestPrimaryPrice(address _indexToken) external view returns(uint);

    function getPrimaryPrice(address _indexToken) external view returns(uint);

    function getFastPrice(address _indexToken, uint _referencePrice) external view returns(uint);

}