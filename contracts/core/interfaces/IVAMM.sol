// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVAMM {

    function allowedPriceDeviation() external view returns(uint);
    function vault() external view returns(address);
    function positionsTracker() external view returns(address);

    function routers(address router) external view returns(bool);
    function whitelistedToken(address indexToken) external view returns(bool);

    function setAllowedPriceDeviation(uint newAllowedPriceDeviation) external;

    function setTokenConfig(address indexToken, uint indexAmount, uint stableAmount, uint referencePrice) external;

    function deleteTokenConfig(address indexToken) external;

    function updateIndex(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta,
        bool long,
        bool increase,
        bool liquidation,
        address feeReceiver
    ) external;

    // test function
    function setPrice(address indexToken, uint indexAmount, uint stableAmount) external;

    function setLiquidity(address indexToken, uint indexAmount, uint stableAmount) external;

    function getData(address indexToken) external view returns(
        uint indexAmount, 
        uint stableAmount, 
        uint liquidity, 
        uint lastUpdateTime
    ); 

    function getPrice(address indexToken) external view returns(uint);

    function preCalculatePrice(
        address indexToken, 
        uint sizeDelta, 
        bool increase, 
        bool long
    ) external view returns(uint newStableAmount, uint newIndexAmount, uint markPrice);

}