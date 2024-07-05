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

    function whitelistedToken(address indexToken) external view returns(bool);
    function updaters(address updater) external view returns(bool);

    function setUpdater(address updater, bool set) external;

    function setDeltaDuration(uint newDeltaDuration) external;

    function setLiquidityDeviation(uint newLiquidityDeviation) external;

    function setTokenConfig(address indexToken, uint maxTotalLongSizes, uint maxTotalShortSizes) external;

    function deleteTokenConfig(address indexToken) external;

    function setMaxTotalSizes(address indexToken, uint maxTotalLongSizes, uint maxTotalShortSizes) external;

    function increaseTotalSizes(address indexToken, uint sizeDelta, uint markPrice, bool long) external;

    function decreaseTotalSizes(address indexToken, uint sizeDelta, uint markPrice, bool long) external;

    function updateTotalPositionsProfit(address[] calldata indexTokens) external;

    function getPositionsData() external view returns(bool isActual, bool hasTradersProfit, uint totalPositionsDelta);

}