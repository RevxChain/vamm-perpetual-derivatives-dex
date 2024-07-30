// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IController {

    function setErrors(string[] calldata errors) external;

    function setTokenConfig(
        address indexToken,
        uint tokenAmount,
        uint stableAmount,
        uint maxTotalLongSizes,
        uint maxTotalShortSizes,
        address tokenPriceFeed,
        uint priceDecimals,
        address ammPool,
        uint poolDecimals
    ) external;

    function setPriceFeedAggregator(address indexToken, address tokenPriceFeed, uint priceDecimals) external;

    function setAmmPool(address indexToken, address ammPool, uint poolDecimals) external;

    function deleteTokenConfig(address indexToken) external;

    function setOracleTokenConfig(
        address indexToken,
        uint price,
        uint refPrice,
        uint maxDelta,
        uint maxCumulativeDelta
    ) external;

    function deleteOracleTokenConfig(address indexToken) external;

    function distributeFees(uint extraRewardAmount) external;
    
}