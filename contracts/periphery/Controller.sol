// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./AddressesRegistry.sol";
import "../libraries/Governable.sol";

import "../core/interfaces/IPositionsTracker.sol";
import "../oracle/interfaces/IFastPriceFeed.sol";
import "../core/interfaces/IMarketRouter.sol";
import "../staking/interfaces/ILPStaking.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../core/interfaces/IOrderBook.sol";
import "../core/interfaces/ILPManager.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVAMM.sol";

contract Controller is AddressesRegistry, Governable, ReentrancyGuard {

    bool public isInitialized;

    function initialize(
        address _vault,
        address _fastPriceFeed,
        address _orderBook,
        address _LPStaking,
        address _govToken,
        address _multiWalletFactory,
        address _stakedSupplyToken,
        address _utilityToken
    ) external onlyHandler(gov) {   
        require(!isInitialized, "Controller: initialized");
        isInitialized = true;

        vault = _vault;

        VAMM = IVault(_vault).VAMM();
        priceFeed = IVault(_vault).priceFeed();
        LPManager = IVault(_vault).LPManager();
        marketRouter = IVault(_vault).marketRouter();
        positionsTracker = IVault(_vault).positionsTracker();
        utilityStorage = IVault(_vault).utilityStorage();
        stable = IVault(_vault).stable();
        liquidityManagerProxy = IVault(_vault).liquidityManager();

        fastPriceFeed = _fastPriceFeed;
        orderBook = _orderBook;
        LPStaking = _LPStaking;
        govToken = _govToken;
        multiWalletFactory = _multiWalletFactory;
        stakedSupplyToken = _stakedSupplyToken;
        utilityToken = _utilityToken;

        (, bytes memory _response) = _multiWalletFactory.staticcall(abi.encodeWithSignature("multiWalletMarketplace()"));
        multiWalletMarketplace = abi.decode(_response, (address));
    }

    function setErrors(string[] calldata errors) external onlyHandler(gov) {
        for(uint i; errors.length > i; i++) IVault(vault).setError(i, errors[i]);
    }

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
    ) external onlyHandler(dao) nonReentrant() { 
        IPriceFeed(priceFeed).setTokenConfig(indexToken, tokenPriceFeed, priceDecimals, ammPool, poolDecimals);

        uint _referencePrice = IPriceFeed(priceFeed).getPrice(indexToken);
        require(_referencePrice > 0, "Controller: invalid price");

        IVault(vault).setTokenConfig(indexToken);
        IVAMM(VAMM).setTokenConfig(indexToken, tokenAmount, stableAmount, _referencePrice);
        IPositionsTracker(positionsTracker).setTokenConfig(indexToken, maxTotalLongSizes, maxTotalShortSizes);
        IMarketRouter(marketRouter).setTokenConfig(indexToken);
        IOrderBook(orderBook).setTokenConfig(indexToken); 
    }

    function setPriceFeedAggregator(
        address indexToken, 
        address tokenPriceFeed, 
        uint priceDecimals
    ) external onlyHandlers() nonReentrant() {
        IPriceFeed(priceFeed).setPriceFeedAggregator(indexToken, tokenPriceFeed, priceDecimals);

        uint _referencePrice = IPriceFeed(priceFeed).getPrice(indexToken);
        require(_referencePrice > 0, "Controller: invalid price");
    }

    function setAmmPool(
        address indexToken, 
        address ammPool, 
        uint poolDecimals
    ) external onlyHandlers() nonReentrant() {
        IPriceFeed(priceFeed).setAmmPool(indexToken, ammPool, poolDecimals);
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(dao) nonReentrant() {  
        IVault(vault).deleteTokenConfig(indexToken); 
        IVAMM(VAMM).deleteTokenConfig(indexToken);
        IPositionsTracker(positionsTracker).deleteTokenConfig(indexToken);
        IMarketRouter(marketRouter).deleteTokenConfig(indexToken);
        IOrderBook(orderBook).deleteTokenConfig(indexToken);
        IPriceFeed(priceFeed).deleteTokenConfig(indexToken);
        IFastPriceFeed(fastPriceFeed).deleteTokenConfig(indexToken);
    }

    function setOracleTokenConfig(
        address indexToken,
        uint price,
        uint refPrice,
        uint maxDelta,
        uint maxCumulativeDelta
    ) external onlyHandler(dao) nonReentrant() { 
        IFastPriceFeed(fastPriceFeed).setTokenConfig(
            indexToken,
            price,
            refPrice,
            maxDelta,
            maxCumulativeDelta
        );
    }

    function deleteOracleTokenConfig(address indexToken) external onlyHandler(dao) nonReentrant() {  
        IFastPriceFeed(fastPriceFeed).deleteTokenConfig(indexToken);
    }

    function distributeFees(uint extraRewardAmount) external onlyHandlers() nonReentrant() {
        ILPManager(LPManager).withdrawFees();
        IVault(vault).withdrawFees();
        address _stable = ILPManager(LPManager).stable();
        uint _amount = IERC20(_stable).balanceOf(address(this));
        IERC20(_stable).approve(LPManager, _amount);
        _amount = ILPManager(LPManager).addLiquidity(_amount);
        IERC20(LPManager).approve(LPStaking, _amount);
        IERC20(govToken).approve(LPStaking, extraRewardAmount);
        ILPStaking(LPStaking).addRewards(_amount, extraRewardAmount);
    }
}