// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "../staking/interfaces/IUtilityStorage.sol";

contract VaultBase is Governable { 
    using Math for uint;
    
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
    address public liquidityManager;

    bool public isInitialized;
    bool public shouldValidatePoolShares;
    bool public extraUsageLiquidityEnabled;

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

    function setBaseMaxLeverage(uint newBaseMaxLeverage) external onlyHandler(dao) {
        validate(newBaseMaxLeverage >= MIN_LEVERAGE, 2);
        baseMaxLeverage = newBaseMaxLeverage;
    }

    function setLiquidationFee(uint newLiquidationFee) external onlyHandler(dao) {
        validate(newLiquidationFee >= MIN_LIQUIDATION_FEE, 3);
        validate(MAX_LIQUIDATION_FEE >= newLiquidationFee, 4);
        liquidationFee = newLiquidationFee;
    }

    function setRemainingLiquidationFee(uint newRemainingLiquidationFee) external onlyHandler(dao) {
        validate(MAX_REMAINING_LIQUIDATION_FEE >= newRemainingLiquidationFee, 8);
        remainingLiquidationFee = newRemainingLiquidationFee;
    }

    function setMinChangeTime(uint newMinChangeTime) external onlyHandlers() {
        validate(MAX_CHANGE_TIME >= newMinChangeTime, 14);
        minChangeTime = newMinChangeTime;
    } 

    function setPoolSharesValidation(bool enableShouldValidatePoolShares) external onlyHandlers() {
        shouldValidatePoolShares = enableShouldValidatePoolShares;
    }

    function setError(uint errorCode, string calldata errorMsg) external onlyHandler(controller) {
        errors[errorCode] = errorMsg;
    }

    function calculatePositionKey(address user, address indexToken, bool long) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(user, indexToken, long));
    }

    function validateLeverage(uint size, uint collateral, address user) internal view {
        uint _usedLeverage = size.mulDiv(Math.PRECISION, collateral); 

        (bool _staker, uint _maxLeverage, , , , ) = IUtilityStorage(utilityStorage).getUserUtility(user);
        if(!_staker) _maxLeverage = baseMaxLeverage;

        validate(_usedLeverage >= MIN_LEVERAGE, 23);
        validate(_maxLeverage >= _usedLeverage, 24);
    }

    function validateLastUpdateTime(uint lastUpdateTime) internal view {
        if(lastUpdateTime > 0) validate(block.timestamp > lastUpdateTime + minChangeTime, 15);
    }

    function calculatePoolIncrease(uint totalPool, uint rate, uint lastUpdate) internal view returns(uint) {
        if(totalPool == 1) return 0;
        return (totalPool * rate * ((block.timestamp - lastUpdate).mulDiv(Math.ACCURACY, Math.ONE_YEAR))) / Math.DOUBLE_ACC;
    }

    function validatePoolShares(
        uint total, 
        uint userDebt, 
        uint sharePool, 
        uint userShareDecrease, 
        uint userEntryShare
    ) internal view {
        validate(total >= userDebt, 26);
        validate(sharePool >= userShareDecrease, 27);
        validate(userEntryShare >= userShareDecrease, 28);
    }

    function validate(bool condition, uint errorCode) internal view {
        require(condition, errors[errorCode]);
    }

    function calculateFeesAndDelta(bool hasProfit, uint fees, uint delta) internal pure returns(uint, uint) {
        if(hasProfit){
            if(fees >= delta){
                fees -= delta;
                delta = 0;
            } else {
                delta -= fees;
                fees = 0;
            }
        } else {
            fees += delta;
            delta = 0;
        }

        return (fees, delta);
    }  

    function getPriceDelta(uint price, uint refPrice) internal pure returns(uint delta) {
        return price > refPrice ? price - refPrice : refPrice - price;
    }
}