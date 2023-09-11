// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IController {

    function vault() external view returns(address);
    function VAMM() external view returns(address);
    function priceFeed() external view returns(address);
    function fastPriceFeed() external view returns(address);
    function LPManager() external view returns(address);
    function orderBook() external view returns(address);
    function marketRouter() external view returns(address);
    function positionsTracker() external view returns(address);
    function LPStaking() external view returns(address);
    function govToken() external view returns(address);

    function setErrors(string[] calldata _errors) external;

    function setTokenConfig(
        address _indexToken,
        uint _tokenAmount,
        uint _stableAmount,
        uint _maxTotalLongSizes,
        uint _maxTotalShortSizes,
        address _priceFeed,
        uint _priceDecimals,
        address _ammPool,
        uint _poolDecimals
    ) external;

    function setPriceFeedAggregator(address _indexToken, address _priceFeed, uint _priceDecimals) external;

    function setAmmPool(address _indexToken, address _ammPool, uint _poolDecimals) external;

    function deleteTokenConfig(address _indexToken) external;

    function setOracleTokenConfig(
        address _indexToken,
        uint _price,
        uint _refPrice,
        uint _maxDelta,
        uint _maxCumulativeDelta
    ) external;

    function deleteOracleTokenConfig(address _indexToken) external;

    function distributeFees(uint _extraRewardAmount) external;
    
}