// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../core/interfaces/IPositionsTracker.sol";
import "../core/interfaces/IMarketRouter.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../core/interfaces/IOrderBook.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVAMM.sol";
import "../libraries/Governable.sol";

contract Controller is Governable, ReentrancyGuard {

    address public vault;
    address public VAMM;
    address public priceFeed;
    address public LPManager;
    address public orderBook;
    address public marketRouter;
    address public positionsTracker;
    
    bool public isInitialized;

    function initialize(
        address _vault,
        address _VAMM,
        address _priceFeed,
        address _LPManager,
        address _orderBook,
        address _marketRouter,
        address _positionsTracker
    ) external onlyHandler(gov) {   
        require(isInitialized == false, "Controller: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        priceFeed = _priceFeed;
        LPManager = _LPManager;
        orderBook = _orderBook;
        marketRouter = _marketRouter;
        positionsTracker = _positionsTracker;
    }

    function setErrors(string[] calldata _errors) external onlyHandler(gov) {
        for (uint i = 0; i < _errors.length; i++) {
            IVault(vault).setError(i, _errors[i]);
        }
    }

    function setTokenConfig(
        address _indexToken,
        uint _tokenAmount,
        uint _stableAmount,
        uint _maxTotalLongSizes,
        uint _maxTotalShortSizes,
        address _priceFeed,
        uint _priceDecimals,
        uint _spreadBasisPoints
    ) external onlyHandler(dao) nonReentrant() { 
        IPriceFeed(priceFeed).setTokenConfig(_indexToken, _priceFeed, _priceDecimals, _spreadBasisPoints);

        uint _referencePrice = IPriceFeed(priceFeed).getPrice(_indexToken);
        require(_referencePrice > 0, "Controller: invalid price");

        IVault(vault).setTokenConfig(_indexToken);
        IVAMM(VAMM).setTokenConfig(_indexToken, _tokenAmount, _stableAmount, _referencePrice);
        IPositionsTracker(positionsTracker).setTokenConfig(_indexToken, _maxTotalLongSizes, _maxTotalShortSizes);
        IMarketRouter(marketRouter).setTokenConfig(_indexToken);
        IOrderBook(orderBook).setTokenConfig(_indexToken); 
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(dao) nonReentrant() {  
        IVault(vault).deleteTokenConfig(_indexToken); 
        IVAMM(VAMM).deleteTokenConfig(_indexToken);
        IPositionsTracker(positionsTracker).deleteTokenConfig(_indexToken);
        IMarketRouter(marketRouter).deleteTokenConfig(_indexToken);
        IOrderBook(orderBook).deleteTokenConfig(_indexToken);
        IPriceFeed(priceFeed).deleteTokenConfig(_indexToken);
    }
}

