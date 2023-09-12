// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../core/interfaces/IPositionsTracker.sol";
import "../oracle/interfaces/IFastPriceFeed.sol";
import "../core/interfaces/IMarketRouter.sol";
import "../staking/interfaces/ILPStaking.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../core/interfaces/IOrderBook.sol";
import "../core/interfaces/ILPManager.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVAMM.sol";
import "../libraries/Governable.sol";

contract Controller is Governable, ReentrancyGuard {

    address public vault;
    address public VAMM;
    address public priceFeed;
    address public fastPriceFeed;
    address public LPManager;
    address public orderBook;
    address public marketRouter;
    address public positionsTracker;
    address public LPStaking;
    address public govToken;
    
    bool public isInitialized;

    function initialize(
        address _vault,
        address _VAMM,
        address _priceFeed,
        address _fastPriceFeed,
        address _LPManager,
        address _orderBook,
        address _marketRouter,
        address _positionsTracker,
        address _LPStaking,
        address _govToken
    ) external onlyHandler(gov) {   
        require(!isInitialized, "Controller: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        priceFeed = _priceFeed;
        fastPriceFeed = _fastPriceFeed;
        LPManager = _LPManager;
        orderBook = _orderBook;
        marketRouter = _marketRouter;
        positionsTracker = _positionsTracker;
        LPStaking = _LPStaking;
        govToken = _govToken;
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
        address _ammPool,
        uint _poolDecimals
    ) external onlyHandler(dao) nonReentrant() { 
        IPriceFeed(priceFeed).setTokenConfig(_indexToken, _priceFeed, _priceDecimals, _ammPool, _poolDecimals);

        uint _referencePrice = IPriceFeed(priceFeed).getPrice(_indexToken);
        require(_referencePrice > 0, "Controller: invalid price");

        IVault(vault).setTokenConfig(_indexToken);
        IVAMM(VAMM).setTokenConfig(_indexToken, _tokenAmount, _stableAmount, _referencePrice);
        IPositionsTracker(positionsTracker).setTokenConfig(_indexToken, _maxTotalLongSizes, _maxTotalShortSizes);
        IMarketRouter(marketRouter).setTokenConfig(_indexToken);
        IOrderBook(orderBook).setTokenConfig(_indexToken); 
    }

    function setPriceFeedAggregator(
        address _indexToken, 
        address _priceFeed, 
        uint _priceDecimals
    ) external onlyHandlers() nonReentrant() {
        IPriceFeed(priceFeed).setPriceFeedAggregator(_indexToken, _priceFeed, _priceDecimals);

        uint _referencePrice = IPriceFeed(priceFeed).getPrice(_indexToken);
        require(_referencePrice > 0, "Controller: invalid price");
    }

    function setAmmPool(
        address _indexToken, 
        address _ammPool, 
        uint _poolDecimals
    ) external onlyHandlers() nonReentrant() {
        IPriceFeed(priceFeed).setAmmPool(_indexToken, _ammPool, _poolDecimals);
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(dao) nonReentrant() {  
        IVault(vault).deleteTokenConfig(_indexToken); 
        IVAMM(VAMM).deleteTokenConfig(_indexToken);
        IPositionsTracker(positionsTracker).deleteTokenConfig(_indexToken);
        IMarketRouter(marketRouter).deleteTokenConfig(_indexToken);
        IOrderBook(orderBook).deleteTokenConfig(_indexToken);
        IPriceFeed(priceFeed).deleteTokenConfig(_indexToken);
        IFastPriceFeed(fastPriceFeed).deleteTokenConfig(_indexToken);
    }

    function setOracleTokenConfig(
        address _indexToken,
        uint _price,
        uint _refPrice,
        uint _maxDelta,
        uint _maxCumulativeDelta
    ) external onlyHandler(dao) nonReentrant() { 
        IFastPriceFeed(fastPriceFeed).setTokenConfig(
            _indexToken,
            _price,
            _refPrice,
            _maxDelta,
            _maxCumulativeDelta
        );
    }

    function deleteOracleTokenConfig(address _indexToken) external onlyHandler(dao) nonReentrant() {  
        IFastPriceFeed(fastPriceFeed).deleteTokenConfig(_indexToken);
    }

    function distributeFees(uint _extraRewardAmount) external onlyHandlers() nonReentrant() {
        ILPManager(LPManager).withdrawFees();
        IVault(vault).withdrawFees();
        address _stable = ILPManager(LPManager).stable();
        uint _amount = IERC20(_stable).balanceOf(address(this));
        IERC20(_stable).approve(LPManager, _amount);
        _amount = ILPManager(LPManager).addLiquidity(_amount);
        IERC20(LPManager).approve(LPStaking, _amount);
        IERC20(govToken).approve(LPStaking, _extraRewardAmount);
        ILPStaking(LPStaking).addRewards(_amount, _extraRewardAmount);
    }
}

