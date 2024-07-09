// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./FlashLoanModule.sol";

import "../periphery/interfaces/ILiquidityManager.sol";

contract Vault is FlashLoanModule {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public constant MAX_BASE_OPERATING_FEE = 50;

    uint public baseOperatingFee;
    uint public maxOperatingFeePriceDeviation;
    uint public operatingFeePriceMultiplier;

    bool public zeroOperatingFee;

    function initialize(
        address _stable,
        address _VAMM,
        address _LPManager,
        address _priceFeed,
        address _positionsTracker,
        address _marketRouter,
        address _controller,
        address _utilityStorage,
        address _liquidityManager
    ) external onlyHandler(gov) validateAddress(_controller) {   
        validate(!isInitialized, 1);
        isInitialized = true;

        stable = _stable;
        VAMM = _VAMM;
        LPManager = _LPManager;
        priceFeed = _priceFeed;
        positionsTracker = _positionsTracker;
        marketRouter = _marketRouter;
        controller = _controller;
        utilityStorage = _utilityStorage;
        liquidityManager = _liquidityManager;

        shouldValidatePoolShares = true;
        cappedBorrowRate = true;
        lastUpdateTotalBorrows = block.timestamp;
        totalBorrows = Math.INIT_LOCK_AMOUNT;
        borrowPool = Math.INIT_LOCK_AMOUNT;
        liquidationFee = MIN_LIQUIDATION_FEE; 
        baseOperatingFee = 10; 
        maxOperatingFeePriceDeviation = 500;
        operatingFeePriceMultiplier = 1000;
        baseMaxLeverage = 250000;
        remainingLiquidationFee = MAX_REMAINING_LIQUIDATION_FEE;
        baseBorrowRatePerYear = 1e16;
        extraBorrowRatePerYear = 2e16;
        utilizationRateKink = 1500;
        minChangeTime = 30;
        fundingPriceMultiplier = 5000;
        minAmountToLoan = 1e6;
        baseLoanFee = 300000;
        flashLoanEnabled = true;
    }

    function setTokenConfig(address indexToken) external onlyHandler(controller) {   
        validate(!whitelistedToken[indexToken], 0);    
        whitelistedToken[indexToken] = true;
        setFundingTokenConfig(indexToken);
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) {   
        validate(whitelistedToken[indexToken], 0);
        whitelistedToken[indexToken] = false;
        deleteFundingTokenConfig(indexToken);
    }

    function setBaseOperatingFee(uint newBaseOperatingFee) external onlyHandler(dao) {
        validate(MAX_BASE_OPERATING_FEE >= newBaseOperatingFee, 5);
        baseOperatingFee = newBaseOperatingFee;
    }

    function setMaxOperatingFeePriceDeviation(uint newMaxOperatingFeePriceDeviation) external onlyHandler(dao) {
        validate(Math.PRECISION >= newMaxOperatingFeePriceDeviation, 6);
        maxOperatingFeePriceDeviation = newMaxOperatingFeePriceDeviation;
    }

    function setOperatingFeePriceMultiplier(uint newOperatingFeePriceMultiplier) external onlyHandler(dao) {
        validate(Math.PRECISION >= newOperatingFeePriceMultiplier, 7);
        operatingFeePriceMultiplier = newOperatingFeePriceMultiplier;
    }

    function setExtraUsageLiquidityEnabled(bool enableExtraUsageLiquidity) external onlyHandler(dao) {
        validate(!ILiquidityManager(liquidityManager).active(), 45);
        extraUsageLiquidityEnabled = enableExtraUsageLiquidity;
    }

    function manualUseLiquidity() external onlyHandler(liquidityManager) {
        useLiquidity();
    }

    function increasePool(uint amount) external onlyHandler(LPManager) {
        poolAmount += amount;

        useLiquidity();
    }

    function decreasePool(
        address user, 
        uint amount, 
        uint underlyingAmount
    ) external onlyHandler(LPManager) {
        poolAmount -= amount;

        IERC20(stable).safeTransfer(user, underlyingAmount);

        if(user != LPManager) useLiquidity();
    }

    function directIncreasePool(uint underlyingAmount) external nonReentrant() {
        uint _balance = IERC20(stable).balanceOf(address(this));
        poolAmount += underlyingAmount.stableToPrecision();
        IERC20(stable).safeTransferFrom(msg.sender, address(this), underlyingAmount); 
        validate(IERC20(stable).balanceOf(address(this)) == _balance + underlyingAmount, 21);
        useLiquidity();
    }

    function increasePosition(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta, 
        bool long, 
        uint markPrice 
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(indexToken);
        setUserUtility(user);
        
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position storage position = positions[_key]; 

        validateLastUpdateTime(position.lastUpdateTime);

        uint _margin;
        if(position.borrowed > Math.INIT_LOCK_AMOUNT){ 
            _margin = collectBorrowFee(_key); 
            position.collateral -= _margin; 
            if(sizeDelta > 0){
                uint _operatingFee = collectOperatingFee(indexToken, sizeDelta, long, true); 
                position.collateral -= _operatingFee; 
                _margin += _operatingFee; 
            } 
        } else {
            collateralDelta -= collectOperatingFee(indexToken, sizeDelta, long, true);
        }

        uint _delta;
        if(position.entryFunding > Math.INIT_LOCK_AMOUNT){
            bool _hasProfit;
            (_delta, _hasProfit) = collectFundingFee(user, indexToken, long);
            _hasProfit ? position.collateral += _delta : position.collateral -= _delta; 
            (_margin, _delta) = calculateFeesAndDelta(_hasProfit, _margin, _delta);
        }

        _margin += sizeDelta - collateralDelta + _delta; 
        borrowMargin(_key, _margin);
        getEntryFunding(_key, indexToken, sizeDelta, long);

        uint _assetAmount = sizeDelta.mulDiv(Math.ACCURACY, markPrice);

        if(position.size > 0) _assetAmount += position.size.mulDiv(Math.ACCURACY, position.entryPrice);

        position.size += sizeDelta;
        position.collateral += collateralDelta;
        position.entryPrice = position.size.mulDiv(Math.ACCURACY, _assetAmount);
        position.lastUpdateTime = block.timestamp;

        validateLeverage(position.size, position.collateral, user);
        validateLiquidatable(user, indexToken, long, false);

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function addCollateral(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external onlyHandler(marketRouter) {   
        validate(whitelistedToken[indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(indexToken);

        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position storage position = positions[_key]; 

        validate(position.size > 0, 16);
        validateLastUpdateTime(position.lastUpdateTime);

        uint _margin = collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(user, indexToken, long); 

        (_margin, _delta) = calculateFeesAndDelta(_hasProfit, _margin, _delta);

        validate(collateralDelta + _delta > _margin, 17);

        uint _collateralNext = position.collateral + collateralDelta - _margin + _delta;
        _margin = _collateralNext - position.collateral;

        borrowMarginRedeem(_key, _margin);

        position.collateral = _collateralNext;
        position.lastUpdateTime = block.timestamp;

        validateLeverage(position.size, position.collateral, user);
        useLiquidity();
    }

    function decreasePosition(
        address user, 
        address indexToken, 
        uint collateralDelta,  
        uint sizeDelta, 
        bool long,
        uint markPrice
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(indexToken);
        setUserUtility(user);

        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position storage position = positions[_key];

        validateLastUpdateTime(position.lastUpdateTime);
        validate(position.size >= sizeDelta, 18);

        uint _margin = position.size - position.collateral; 
        position.collateral -= 
        collectOperatingFee(indexToken, sizeDelta, long, false) + collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(user, indexToken, long); 
        _hasProfit ? position.collateral += _delta : position.collateral -= _delta;

        if(long && markPrice > position.entryPrice || !long && position.entryPrice > markPrice){
            _hasProfit = true;
        } else {
            _hasProfit = false;
        }

        _decreasePosition(
            user, 
            indexToken,
            collateralDelta, 
            sizeDelta,
            markPrice,
            _margin,
            long,
            _hasProfit
        );
        
        if(position.size > 0){
            validateLeverage(position.size, position.collateral, user);
            validateLiquidatable(user, indexToken, long, false);
        }

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function withdrawCollateral(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external onlyHandler(marketRouter) {   
        validate(whitelistedToken[indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(indexToken);

        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position storage position = positions[_key];

        validateLastUpdateTime(position.lastUpdateTime);
    
        uint _borrowFee = collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(user, indexToken, long); 
        _hasProfit ? position.collateral += _delta : position.collateral -= _delta;

        validate(position.collateral >= collateralDelta + _borrowFee, 19);
        uint _collateralNext = position.collateral - collateralDelta - _borrowFee; 
        uint _margin = position.collateral - _collateralNext; 
        
        borrowMargin(_key, _margin); 

        position.collateral = _collateralNext; 
        position.lastUpdateTime = block.timestamp;

        collateralDelta = collateralDelta.precisionToStable();
        IERC20(stable).safeTransfer(user, collateralDelta);
        
        validateLeverage(position.size, position.collateral, user);
        validateLiquidatable(user, indexToken, long, false);
        useLiquidity();
    }

    function serviceWithdrawCollateral(
        address user, 
        address indexToken, 
        bool long
    ) external onlyHandler(marketRouter) {
        validate(!whitelistedToken[indexToken], 0);
        updateTotalBorrows();

        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];

        validate(position.size > 0, 16);

        uint _collateralDelta = position.collateral;
        uint _margin = position.size - _collateralDelta; 
        uint _borrowFee = preCalculateUserBorrowDebt(_key); 

        if(_borrowFee >= _collateralDelta){
            _margin += _borrowFee - _collateralDelta; 
            collectBorrowFee(_key);
            _collateralDelta = 0;
        } else {
            _collateralDelta -= collectBorrowFee(_key);
        }

        borrowMarginRedeem(_key, _margin);

        if(_collateralDelta > 0){
            _collateralDelta = _collateralDelta.precisionToStable();
            IERC20(stable).safeTransfer(user, _collateralDelta);
        }

        delete positions[_key];
        useLiquidity();
    }

    function liquidatePosition(
        address user,  
        address indexToken,
        uint sizeDelta,
        bool long, 
        address feeReceiver
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(indexToken);
        setUserUtility(user);

        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];

        uint _collateral = position.collateral; 
        uint _margin = sizeDelta - _collateral;  
        uint _remainingLiquidationFee = liquidationFee; 
        uint _fee = preCalculateUserDebt(_key) - _margin;  

        _collateral > _remainingLiquidationFee ? _collateral -= _remainingLiquidationFee : _collateral = 0; 

        if(_fee >= _collateral){
            _margin += _fee - _collateral; 
            collectBorrowFee(_key);
            _collateral = 0;
        } else {
            _collateral -= collectBorrowFee(_key); 
            _fee = calculateOperationFeeAmount(indexToken, sizeDelta, long, false); 
            if(_fee >= _collateral){
                poolAmount += _collateral;
                _collateral = 0;
            } else {
                _collateral -= collectOperatingFee(indexToken, sizeDelta, long, false); 
                bool _hasProfit;
                (_fee, _hasProfit, , ) = preCalculateUserFundingFee(user, indexToken, long);
                
                if(!_hasProfit && _fee > _collateral){
                    poolAmount += _collateral;
                    _collateral = 0;
                } else {
                    if(!_hasProfit && _collateral >= _fee){
                        collectFundingFee(user, indexToken, long); 
                        _collateral -= _fee;
                    } else {
                        collectFundingFee(user, indexToken, long); 
                        _collateral += _fee;
                    }
                }

                _remainingLiquidationFee = _collateral.mulDiv(remainingLiquidationFee, Math.PRECISION);
                _collateral -= _remainingLiquidationFee; 
                _remainingLiquidationFee += liquidationFee; 
            }
        }

        borrowMarginRedeem(_key, _margin);
        fundingFeeRedeem(_key, indexToken, sizeDelta, long);
    
        if(_collateral > 0) poolAmount += _collateral;

        _remainingLiquidationFee = _remainingLiquidationFee.precisionToStable();
        IERC20(stable).safeTransfer(feeReceiver, _remainingLiquidationFee);

        delete positions[_key];

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function validateLiquidate(
        address user, 
        address indexToken, 
        bool long
    ) public view returns(uint liquidatePrice, bool liquidatable) {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];

        if(position.size == 0) return (0, false); 

        (uint _collateral, uint _markPrice) = (position.collateral, IVAMM(VAMM).getPrice(indexToken));
        (uint _fees, uint _delta) = calculateFees(user, indexToken, long);

        if(_collateral + _delta > _fees){
            _collateral = _collateral + _delta - _fees; 
        } else {
            return (_markPrice, true);
        }

        uint _deviationToLiquidate = Math.PRECISION.mulDiv(Math.PRECISION, (position.size * Math.PRECISION  / _collateral));
        
        liquidatePrice = long ? 
        (Math.PRECISION * position.entryPrice - position.entryPrice * _deviationToLiquidate) / Math.PRECISION : 
        position.entryPrice.mulDiv((Math.PRECISION + _deviationToLiquidate), Math.PRECISION);

        liquidatable = long ? liquidatePrice >= _markPrice : _markPrice >= liquidatePrice;
    }

    function preCalculatePositionDelta( 
        address user, 
        address indexToken, 
        bool long
    ) public view returns(bool hasProfit, uint delta) {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];
        if(position.size == 0) return (false, 0);
        
        (uint _markPrice, uint _entryPrice) = (IVAMM(VAMM).getPrice(indexToken), position.entryPrice);
        (uint _fees, uint _delta) = calculateFees(user, indexToken, long);

        delta = position.size.mulDiv(getPriceDelta(_entryPrice, _markPrice), _entryPrice);
        hasProfit = long ? _markPrice > _entryPrice : _entryPrice > _markPrice;
        if(hasProfit){
            if(delta + _delta > _fees){
                delta = delta + _delta - _fees;
            } else {
                delta = _fees - delta - _delta;
                hasProfit = false;
            }
        } else {
            delta = delta + _fees - _delta;
        }
    }

    function calculateOperationFeeAmount( 
        address indexToken, 
        uint sizeDelta, 
        bool long, 
        bool increase
    ) public view returns(uint) {
        return sizeDelta.mulDiv(calculateOperatingFee(indexToken, long, increase), Math.PRECISION);
    }

    function calculateOperatingFee(address indexToken, bool long, bool increase) public view returns(uint) {
        if(zeroOperatingFee) return 0;
        uint _vammPrice = IVAMM(VAMM).getPrice(indexToken);
        uint _feedPrice = IPriceFeed(priceFeed).getPrice(indexToken);
        uint _priceDelta = getPriceDelta(_vammPrice, _feedPrice).mulDiv(Math.PRECISION, _vammPrice);
        if(_vammPrice > _feedPrice){
            if(increase && long || !increase && !long) return calculateOperatingFeeInternal(_priceDelta);
        }
        if(_vammPrice < _feedPrice){
            if(increase && !long || !increase && long) return calculateOperatingFeeInternal(_priceDelta);
        }
        return baseOperatingFee;
    }

    function validateLiquidatable(address user, address indexToken, bool long, bool condition) public view {
        (, bool _liquidatable) = validateLiquidate(user, indexToken, long);
        validate(_liquidatable == condition, 22);
    }

    function getPosition(
        address user, 
        address indexToken, 
        bool long
    ) public view returns(uint, uint, uint, uint, bool, uint) {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];
        (bool _hasProfit, uint _delta) = preCalculatePositionDelta(user, indexToken, long);
        return (
            position.collateral, 
            position.size, 
            position.entryPrice,  
            position.lastUpdateTime,
            _hasProfit,
            _delta
        );
    }

    function calculateOperatingFeeInternal(uint priceDelta) internal view returns(uint) {
        return priceDelta >= maxOperatingFeePriceDeviation ? 
        MAX_BASE_OPERATING_FEE + baseOperatingFee : 
        priceDelta.mulDiv(operatingFeePriceMultiplier, Math.PRECISION) + baseOperatingFee;
    }

    function calculateFees(
        address user, 
        address indexToken, 
        bool long
    ) internal view returns(uint fees, uint delta) {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position memory position = positions[_key];
        fees = preCalculateUserBorrowDebt(_key);

        (bool _staker, , bool _operatingFee, , , ) = IUtilityStorage(utilityStorage).getUserUtility(user);
        if(!_staker || !_operatingFee) fees += calculateOperationFeeAmount(indexToken, position.size, long, false);

        bool _hasProfit;
        (delta, _hasProfit, ,) = preCalculateUserFundingFee(user, indexToken, long);

        (fees, delta) = calculateFeesAndDelta(_hasProfit, fees, delta);
    }

    function collectOperatingFee(
        address indexToken, 
        uint sizeDelta, 
        bool long, 
        bool increase
    ) internal returns(uint operatingFeeAmount) {
        operatingFeeAmount = calculateOperationFeeAmount(indexToken, sizeDelta, long, increase);
        poolAmount += operatingFeeAmount;
    }

    function setUserUtility(address user) internal {
        (bool _staker, , bool _operatingFee, , , ) = IUtilityStorage(utilityStorage).getUserUtility(user);
        if(_staker && _operatingFee) utilityDecreaseOperationFee(true);
    }

    function utilityDecreaseOperationFee(bool zeroFee) internal {
        zeroOperatingFee = zeroFee;
    }

    function useLiquidity() internal {
        if(!extraUsageLiquidityEnabled) return;
        bool _active = ILiquidityManager(liquidityManager).active();
        uint _amount;
        if(_active){
            (_active, _amount) = ILiquidityManager(liquidityManager).checkRemove(true);
            if(_active){
                (bool _success, uint _earnedAmount) = ILiquidityManager(liquidityManager).removeLiquidity(_amount);
                if(_success) poolAmount += _earnedAmount;
            } 
        } else {
            (_active, _amount) = ILiquidityManager(liquidityManager).checkUsage(true);
            if(_active){
                IERC20(stable).safeTransfer(liquidityManager, _amount);
                ILiquidityManager(liquidityManager).provideLiquidity(_amount);
            }
        }
    }

    function _decreasePosition(
        address user, 
        address indexToken,
        uint collateralDelta, 
        uint sizeDelta,
        uint markPrice,
        uint margin,
        bool long,
        bool hasProfit
    ) internal {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Position storage position = positions[_key];
        collateralDelta = position.size == sizeDelta ? position.collateral : collateralDelta; 
        validate(position.collateral >= collateralDelta, 29);
        
        uint _priceDelta = getPriceDelta(position.entryPrice, markPrice);
        uint _sizeNext = position.size - sizeDelta; 
        uint _realizedPnL = (position.size * _priceDelta / position.entryPrice) - (_sizeNext * _priceDelta / position.entryPrice); 
        uint _collateralNext = position.collateral - collateralDelta; 
        uint _marginNext = _sizeNext - _collateralNext; 

        if(!hasProfit) validate(collateralDelta >= _realizedPnL, 30);

        if(_marginNext > margin){
            margin = _marginNext - margin;
            borrowMargin(_key, margin); 
        } else {
            margin = margin - _marginNext; 
            borrowMarginRedeem(_key, margin);
        }

        if(_sizeNext > position.size){
            margin = _sizeNext - position.size;
            getEntryFunding(_key, indexToken, margin, long);
        } else {
            margin = position.size - _sizeNext;
            fundingFeeRedeem(_key, indexToken, margin, long);
        }

        if(_sizeNext > 0){
            position.size = _sizeNext; 
            position.collateral = _collateralNext; 
            position.lastUpdateTime = block.timestamp;
        } else {
            delete positions[_key];
        }
        
        // margin = income {stack too deep prevent}
        margin = hasProfit ? collateralDelta + _realizedPnL : collateralDelta - _realizedPnL; 
        hasProfit ? poolAmount -= _realizedPnL : poolAmount += _realizedPnL;

        if(hasProfit || margin > 0){
            margin = margin.precisionToStable();
            IERC20(stable).safeTransfer(user, margin);
        }
    }
}