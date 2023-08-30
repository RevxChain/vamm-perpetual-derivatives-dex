// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

contract PositionsTracker is Governable, ReentrancyGuard {
    using Math for uint;

    address public VAMM;
    address public LPManager;
    address public stable;
    address public vault;

    bool public isInitialized;

    mapping(address => bool) public whitelistedToken;
    mapping(address => Config) public configs;

    struct Config {
        uint totalLongSizes;
        uint totalShortSizes;
        uint totalLongAssets;
        uint totalShortAssets;
        uint maxTotalLongSizes;
        uint maxTotalShortSizes;
    }

    modifier whitelisted(address _token, bool _include) {
        require(whitelistedToken[_token] == _include, "PositionsTracker: not whitelisted");
        _;
    }

    function initialize(
        address _vault,
        address _VAMM,
        address _controller
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(!isInitialized, "PositionsTracker: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        controller = _controller;
    }

    function setTokenConfig(
        address _indexToken,
        uint _maxTotalLongSizes,
        uint _maxTotalShortSizes
    ) external onlyHandler(controller) whitelisted(_indexToken, false) {   
        Config storage config = configs[_indexToken];
        whitelistedToken[_indexToken] = true;
        config.maxTotalLongSizes = _maxTotalLongSizes;
        config.maxTotalShortSizes = _maxTotalShortSizes;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {   
        whitelistedToken[_indexToken] = false;

        delete configs[_indexToken];
    }

    function setMaxTotalSizes(
        address _indexToken, 
        uint _maxTotalLongSizes, 
        uint _maxTotalShortSizes
    ) external onlyHandlers() whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken];
        require(config.totalLongSizes > _maxTotalLongSizes, "PositionsTracker: actual long sizes exceeded");
        require(config.totalShortSizes > _maxTotalShortSizes, "PositionsTracker: actual short sizes exceeded");
        config.maxTotalLongSizes = _maxTotalLongSizes;
        config.maxTotalShortSizes = _maxTotalShortSizes;
    }

    function increaseTotalSizes(
        address _indexToken, 
        uint _sizeDelta, 
        uint _markPrice, 
        bool _long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[_indexToken];
        uint _assetsAmount = _sizeDelta / _markPrice;
        if(_long){
            require(
                config.maxTotalLongSizes > config.totalLongSizes + _sizeDelta, 
                "PositionsTracker: actual long sizes exceeded"
            );
            config.totalLongSizes += _sizeDelta; 
            config.totalLongAssets += _assetsAmount;
        } else {
            require(
                config.maxTotalShortSizes > config.totalShortSizes + _sizeDelta, 
                "PositionsTracker: actual short sizes exceeded"
            );
            config.totalShortSizes += _sizeDelta;
            config.totalShortAssets += _assetsAmount;
        }
    }

    function decreaseTotalSizes(
        address _indexToken, 
        uint _sizeDelta, 
        uint _markPrice, 
        bool _long
    ) external onlyHandler(VAMM) {
        Config storage config = configs[_indexToken];
        uint _assetsAmount = _sizeDelta / _markPrice;
        if(_long){
            config.totalLongSizes -= _sizeDelta; 
            config.totalLongAssets > _assetsAmount ? config.totalLongAssets -= _assetsAmount : 0;
        } else {
            config.totalShortSizes -= _sizeDelta;
            config.totalShortAssets > _assetsAmount ? config.totalShortAssets -= _assetsAmount : 0;
        }
    }
}