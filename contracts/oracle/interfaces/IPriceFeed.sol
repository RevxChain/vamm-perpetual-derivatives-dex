// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPriceFeed {

    function getPrice(address _indexToken) external view returns(uint);

    // test function
    function setPrice(address _indexToken, uint _price) external;

    function setTokenConfig(
        address _indexToken,
        address _priceFeed,
        uint _priceDecimals,
        uint _spreadBasisPoints
    ) external;

    function deleteTokenConfig(address _indexToken) external;

    function setIsFastPriceEnabled(bool _isEnabled) external;

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;

    function setPriceSampleSpace(uint _priceSampleSpace) external;

    function setSpreadBasisPoints(address _indexToken, uint _spreadBasisPoints) external;

    function getPrice(address _indexToken, bool _maximise) external view returns(uint);

    function getLatestPrimaryPrice(address _indexToken) external view returns(uint);

    function getPrimaryPrice(address _indexToken, bool _maximise) external view returns(uint);

    function getFastPrice(address _indexToken, uint _referencePrice, bool _maximise) external view returns(uint);

}