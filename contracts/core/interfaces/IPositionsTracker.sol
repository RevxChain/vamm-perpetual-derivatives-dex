// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPositionsTracker {
 
    function setTokenConfig(address _indexToken, uint _maxTotalLongSizes, uint _maxTotalShortSizes) external;

    function deleteTokenConfig(address _indexToken) external;

    function setMaxTotalSizes(address _indexToken, uint _maxTotalLongSizes, uint _maxTotalShortSizes) external;

    function increaseTotalSizes(address _indexToken, uint _sizeDelta, uint _markPrice, bool _long) external;

    function decreaseTotalSizes(address _indexToken, uint _sizeDelta, uint _markPrice, bool _long) external;

    function getConfigData(address _indexToken) external view returns(
        uint totalLongSizes, 
        uint totalShortSizes, 
        uint totalLongAssets, 
        uint totalShortAssets, 
        uint maxTotalLongSizes, 
        uint maxTotalShortSizes
    );

}