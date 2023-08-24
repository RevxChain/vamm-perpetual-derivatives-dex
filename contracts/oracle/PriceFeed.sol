// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IPriceAggregator.sol";
import "./interfaces/IFastPriceFeed.sol";
import "../libraries/Governable.sol";

contract PriceFeed is Governable, ReentrancyGuard {

    uint public constant ACCURACY = 1e18;
    uint public constant PRECISION = 10000;

    uint public priceSampleSpace;

    address public fastPriceFeed;
    address public controller;

    bool public isFastPriceEnabled;
    bool public favorPrimaryPrice;
    bool public isInitialized;
    
    mapping(address => bool) public whitelistedToken;
    mapping(address => Config) public configs;

    struct Config {
        address priceFeed;
        uint priceDecimals;
    }

    modifier whitelisted(address _indexToken, bool _include){
        require(whitelistedToken[_indexToken] == _include, "PriceFeed: invalid whitelisted");
        _;
    }

    function initialize(address _fastPriceFeed, address _controller) external onlyHandler(gov) {  
        require(isInitialized == false, "PriceFeed: initialized");
        isInitialized = true;

        fastPriceFeed = _fastPriceFeed;
        controller = _controller;

        isFastPriceEnabled = true;
        favorPrimaryPrice = false;
        priceSampleSpace = 3;
    }

    function setTokenConfig(
        address _indexToken,
        address _priceFeed,
        uint _priceDecimals
    ) external onlyHandler(controller) whitelisted(_indexToken, false) {
        Config storage config = configs[_indexToken]; 
        config.priceFeed = _priceFeed;
        config.priceDecimals = _priceDecimals;
        whitelistedToken[_indexToken] = true;
    }

    function setPriceFeedAggregator(
        address _indexToken, 
        address _priceFeed, 
        uint _priceDecimals
    ) external onlyHandler(controller) whitelisted(_indexToken, true) {
        Config storage config = configs[_indexToken]; 

        require(config.priceFeed == address(0), "PriceFeed: already set");
        config.priceFeed = _priceFeed;
        config.priceDecimals = _priceDecimals;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {
        delete configs[_indexToken];
        whitelistedToken[_indexToken] = false;
    }

    function setIsFastPriceEnabled(bool _isFastPriceEnabled) external onlyHandlers() {
        isFastPriceEnabled = _isFastPriceEnabled;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external onlyHandlers() {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(uint _priceSampleSpace) external onlyHandlers() {
        require(_priceSampleSpace > 0, "PriceFeed: invalid priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
    }

    function getPrice(address _indexToken) external view returns(uint price) {
        price = getPrimaryPrice(_indexToken);
        if(favorPrimaryPrice == true && price != 0){
            return price;
        } else {
            if(isFastPriceEnabled || price == 0) price = getFastPrice(_indexToken, price);
        }
        validatePrice(int(price));
    }

    function getConfig(address _indexToken) external view returns(address, uint) {
        Config memory config = configs[_indexToken]; 
        return (config.priceFeed, config.priceDecimals);
    }

    function getLatestPrimaryPrice(address _indexToken) external view returns(uint) {
        address _priceFeedAddress = configs[_indexToken].priceFeed;
        require(_priceFeedAddress != address(0), "PriceFeed: invalid price feed");

        int price = IPriceAggregator(_priceFeedAddress).latestAnswer();
        validatePrice(price);

        return uint(price);
    }

    function getPrimaryPrice(address _indexToken) public view returns(uint) {
        address _priceFeedAddress = configs[_indexToken].priceFeed;
        if(_priceFeedAddress == address(0)) return 0;

        IPriceAggregator priceFeed = IPriceAggregator(_priceFeedAddress);

        uint _price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) { break; }
            uint p;

            if (i == 0) {
                int _p = priceFeed.latestAnswer();
                validatePrice(_p);
                p = uint(_p);
            } else {
                (, int _p, , ,) = priceFeed.getRoundData(roundId - i);
                validatePrice(_p);
                p = uint(_p);
            }

            if (_price == 0) {
                _price = p;
                continue;
            }
        }

        validatePrice(int(_price));
        uint _priceDecimals = configs[_indexToken].priceDecimals;
        return _price * ACCURACY / (10 ** _priceDecimals);
    }

    function getFastPrice(address _indexToken, uint _referencePrice) public view returns(uint) {
        if(fastPriceFeed == address(0)) return _referencePrice;
        return IFastPriceFeed(fastPriceFeed).getPrice(_indexToken, _referencePrice);
    }

    function validatePrice(int _price) internal pure {
        require(_price > 0, "PriceFeed: invalid price");
    }
}