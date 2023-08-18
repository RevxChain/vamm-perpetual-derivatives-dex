// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVAMM {

    function allowedPriceDeviation() external view returns(uint);
    function vault() external view returns(address);
    function positionsTracker() external view returns(address);
    function controller() external view returns(address);
    function routers(address _router) external view returns(bool);
    function whitelistedToken(address _indexToken) external view returns(bool);

    function setAllowedPriceDeviation(uint _allowedPriceDeviation) external;

    function setTokenConfig(address _indexToken, uint _indexAmount, uint _stableAmount, uint _referencePrice) external;

    function deleteTokenConfig(address _indexToken) external;

    function updateIndex(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta,
        bool _long,
        bool _increase,
        bool _liquidation,
        address _feeReceiver
    ) external;

    // test function
    function setPrice(address _indexToken, uint _indexAmount, uint _stableAmount) external;

    function setLiquidity(address _indexToken, uint _indexAmount, uint _stableAmount) external;

    function getData(address _indexToken) external view returns(
        uint indexAmount, 
        uint stableAmount, 
        uint liquidity, 
        uint lastUpdateTime
    ); 

    function getPrice(address _indexToken) external view returns(uint);

    function preCalculatePrice(
        address _indexToken, 
        uint _sizeDelta, 
        bool _increase, 
        bool _long
    ) external view returns(uint newStableAmount, uint newIndexAmount, uint markPrice);

}