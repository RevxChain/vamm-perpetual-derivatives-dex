// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../staking/interfaces/IUtilityStorage.sol";
import "../libraries/Governable.sol";
import "../libraries/Math.sol";

contract VaultBase is Governable { 
    
    uint public constant MIN_LEVERAGE = 11000; 
    uint public constant MIN_LIQUIDATION_FEE = 5e18; 
    uint public constant MAX_LIQUIDATION_FEE = 50e18; 
    uint public constant MAX_REMAINING_LIQUIDATION_FEE = 125; 
    uint public constant MAX_CHANGE_TIME = 300;
    
    uint public poolAmount; 
    uint public minChangeTime;
    uint public baseMaxLeverage;
    uint public liquidationFee;
    uint public remainingLiquidationFee;
    
    address public VAMM;
    address public LPManager;
    address public stable;
    address public priceFeed;
    address public positionsTracker;
    address public marketRouter;
    address public utilityStorage;

    bool public isInitialized;
    bool public shouldValidatePoolShares;

    mapping(address => bool) public whitelistedToken;
    mapping(uint => string) public errors;
    mapping(bytes32 => Position) public positions;

    struct Position {
        uint collateral;
        uint size;
        uint entryPrice;
        uint borrowed;  
        uint entryFunding;
        uint lastUpdateTime; 
    }

    function setBaseMaxLeverage(uint _baseMaxLeverage) external onlyHandler(dao) {
        validate(_baseMaxLeverage >= MIN_LEVERAGE, 2);
        baseMaxLeverage = _baseMaxLeverage;
    }

    function setLiquidationFee(uint _liquidationFee) external onlyHandler(dao) {
        validate(_liquidationFee >= MIN_LIQUIDATION_FEE, 3);
        validate(MAX_LIQUIDATION_FEE >= _liquidationFee, 4);
        liquidationFee = _liquidationFee;
    }

    function setRemainingLiquidationFee(uint _remainingLiquidationFee) external onlyHandler(dao) {
        validate(MAX_REMAINING_LIQUIDATION_FEE >= _remainingLiquidationFee, 8);
        remainingLiquidationFee = _remainingLiquidationFee;
    }

    function setMinChangeTime(uint _minChangeTime) external onlyHandlers() {
        validate(MAX_CHANGE_TIME >= _minChangeTime, 14);
        minChangeTime = _minChangeTime;
    } 

    function setPoolSharesValidation(bool _shouldValidatePoolShares) external onlyHandlers() {
        shouldValidatePoolShares = _shouldValidatePoolShares;
    }

    function setError(uint _errorCode, string calldata _error) external onlyHandler(controller) {
        errors[_errorCode] = _error;
    }

    function calculatePositionKey(address _user, address _indexToken, bool _long) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(_user, _indexToken, _long));
    }

    function validateLeverage(uint _size, uint _collateral, address _user) internal view {
        uint _usedLeverage = _size * Math.PRECISION  / _collateral; 

        (bool _staker, uint _maxLeverage, , , , ) = IUtilityStorage(utilityStorage).getUserUtility(_user);
        if(!_staker) _maxLeverage = baseMaxLeverage;

        validate(_usedLeverage >= MIN_LEVERAGE, 23);
        validate(_maxLeverage >= _usedLeverage, 24);
    }

    function validateLastUpdateTime(uint _lastUpdateTime) internal view {
        if(_lastUpdateTime > 0) validate(block.timestamp > _lastUpdateTime + minChangeTime, 15);
    }

    function calculatePoolIncrease(uint _totalPool, uint _rate, uint _lastUpdate) internal view returns(uint) {
        return (_totalPool * _rate * ((block.timestamp - _lastUpdate) * Math.ACCURACY / Math.ONE_YEAR)) / Math.DOUBLE_ACC;
    }

    function validatePoolShares(
        uint _total, 
        uint _userDebt, 
        uint _sharePool, 
        uint _userShareDecrease, 
        uint _userEntryShare
    ) internal view {
        validate(_total >= _userDebt, 26);
        validate(_sharePool >= _userShareDecrease, 27);
        validate(_userEntryShare >= _userShareDecrease, 28);
    }

    function validate(bool _condition, uint _errorCode) internal view {
        require(_condition, errors[_errorCode]);
    }

    function calculateFeesAndDelta(bool _hasProfit, uint _fees, uint _delta) internal pure returns(uint, uint) {
        if(_hasProfit){
            if(_fees >= _delta){
                _fees -= _delta;
                _delta = 0;
            } else {
                _delta -= _fees;
                _fees = 0;
            }
        } else {
            _fees += _delta;
            _delta = 0;
        }

        return (_fees, _delta);
    }  

    function getPriceDelta(uint _price, uint _refPrice) internal pure returns(uint delta) {
        return _price > _refPrice ? _price - _refPrice : _refPrice - _price;
    }
}