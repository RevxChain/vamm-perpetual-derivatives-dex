// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPositionsTracker {

    function whitelistedTokensCount() external view returns(uint);
    function totalPositionsDelta() external view returns(uint);
    function lastUpdatedTime() external view returns(uint);
    function deltaDuration() external view returns(uint);
    function lastPoolAmount() external view returns(uint);
    function liquidityDeviation() external view returns(uint);
    function VAMM() external view returns(address);
    function LPManager() external view returns(address);
    function stable() external view returns(address);
    function vault() external view returns(address);
    function hasTradersProfit() external view returns(bool);

    function whitelistedToken(address _indexToken) external view returns(bool);
    function updaters(address _updater) external view returns(bool);

    function setUpdater(address _updater, bool _bool) external;

    function setDeltaDuration(uint _deltaDuration) external;

    function setLiquidityDeviation(uint _liquidityDeviation) external;

    function setTokenConfig(address _indexToken, uint _maxTotalLongSizes, uint _maxTotalShortSizes) external;

    function deleteTokenConfig(address _indexToken) external;

    function setMaxTotalSizes(address _indexToken, uint _maxTotalLongSizes, uint _maxTotalShortSizes) external;

    function increaseTotalSizes(address _indexToken, uint _sizeDelta, uint _markPrice, bool _long) external;

    function decreaseTotalSizes(address _indexToken, uint _sizeDelta, uint _markPrice, bool _long) external;

    function updateTotalPositionsProfit(address[] calldata _indexTokens) external;

    function getPositionsData() external view returns(bool isActual, bool hasTradersProfit, uint totalPositionsDelta);

}