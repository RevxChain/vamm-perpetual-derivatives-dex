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

    function setTokenConfig(address _indexToken) external onlyHandler(controller) {   
        validate(!whitelistedToken[_indexToken], 0);    
        whitelistedToken[_indexToken] = true;
        setFundingTokenConfig(_indexToken);
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) {   
        validate(whitelistedToken[_indexToken], 0);
        whitelistedToken[_indexToken] = false;
        deleteFundingTokenConfig(_indexToken);
    }

    function setBaseOperatingFee(uint _baseOperatingFee) external onlyHandler(dao) {
        validate(MAX_BASE_OPERATING_FEE >= _baseOperatingFee, 5);
        baseOperatingFee = _baseOperatingFee;
    }

    function setMaxOperatingFeePriceDeviation(uint _maxOperatingFeePriceDeviation) external onlyHandler(dao) {
        validate(Math.PRECISION >= _maxOperatingFeePriceDeviation, 6);
        maxOperatingFeePriceDeviation = _maxOperatingFeePriceDeviation;
    }

    function setOperatingFeePriceMultiplier(uint _operatingFeePriceMultiplier) external onlyHandler(dao) {
        validate(Math.PRECISION >= _operatingFeePriceMultiplier, 7);
        operatingFeePriceMultiplier = _operatingFeePriceMultiplier;
    }

    function setExtraUsageLiquidityEnabled(bool _extraUsageLiquidityEnabled) external onlyHandler(dao) {
        validate(!ILiquidityManager(liquidityManager).active(), 45);
        extraUsageLiquidityEnabled = _extraUsageLiquidityEnabled;
    }

    function manualUseLiquidity() external onlyHandler(liquidityManager) {
        useLiquidity();
    }

    function increasePool(uint _amount) external onlyHandler(LPManager) {
        poolAmount += _amount;

        useLiquidity();
    }

    function decreasePool(
        address _user, 
        uint _amount, 
        uint _underlyingAmount
    ) external onlyHandler(LPManager) {
        poolAmount -= _amount;

        IERC20(stable).safeTransfer(_user, _underlyingAmount);

        if(_user != LPManager) useLiquidity();
    }

    function directIncreasePool(uint _underlyingAmount) external nonReentrant() {
        uint _balance = IERC20(stable).balanceOf(address(this));
        poolAmount += _underlyingAmount.stableToPrecision();
        IERC20(stable).safeTransferFrom(msg.sender, address(this), _underlyingAmount); 
        validate(IERC20(stable).balanceOf(address(this)) == _balance + _underlyingAmount, 21);
        useLiquidity();
    }

    function increasePosition(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta, 
        bool _long, 
        uint _markPrice 
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[_indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(_indexToken);
        setUserUtility(_user);
        
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position storage position = positions[_key]; 

        validateLastUpdateTime(position.lastUpdateTime);

        uint _margin;
        if(position.borrowed > Math.INIT_LOCK_AMOUNT){ 
            _margin = collectBorrowFee(_key); 
            position.collateral -= _margin; 
            if(_sizeDelta > 0){
                uint _operatingFee = collectOperatingFee(_indexToken, _sizeDelta, _long, true); 
                position.collateral -= _operatingFee; 
                _margin += _operatingFee; 
            } 
        } else {
            _collateralDelta -= collectOperatingFee(_indexToken, _sizeDelta, _long, true);
        }

        uint _delta;
        if(position.entryFunding > Math.INIT_LOCK_AMOUNT){
            bool _hasProfit;
            (_delta, _hasProfit) = collectFundingFee(_user, _indexToken, _long);
            _hasProfit ? position.collateral += _delta : position.collateral -= _delta; 
            (_margin, _delta) = calculateFeesAndDelta(_hasProfit, _margin, _delta);
        }

        _margin += _sizeDelta - _collateralDelta + _delta; 
        borrowMargin(_key, _margin);
        getEntryFunding(_key, _indexToken, _sizeDelta, _long);

        uint _assetAmount = _sizeDelta * Math.ACCURACY / _markPrice;

        if(position.size > 0) _assetAmount += position.size * Math.ACCURACY / position.entryPrice;

        position.size += _sizeDelta;
        position.collateral += _collateralDelta;
        position.entryPrice = position.size * Math.ACCURACY / _assetAmount;
        position.lastUpdateTime = block.timestamp;

        validateLeverage(position.size, position.collateral, _user);
        validateLiquidatable(_user, _indexToken, _long, false);

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function addCollateral(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external onlyHandler(marketRouter) {   
        validate(whitelistedToken[_indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(_indexToken);

        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position storage position = positions[_key]; 

        validate(position.size > 0, 16);
        validateLastUpdateTime(position.lastUpdateTime);

        uint _margin = collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(_user, _indexToken, _long); 

        (_margin, _delta) = calculateFeesAndDelta(_hasProfit, _margin, _delta);

        validate(_collateralDelta + _delta > _margin, 17);

        uint _collateralNext = position.collateral + _collateralDelta - _margin + _delta;
        _margin = _collateralNext - position.collateral;

        borrowMarginRedeem(_key, _margin);

        position.collateral = _collateralNext;
        position.lastUpdateTime = block.timestamp;

        validateLeverage(position.size, position.collateral, _user);
        useLiquidity();
    }

    function decreasePosition(
        address _user, 
        address _indexToken, 
        uint _collateralDelta,  
        uint _sizeDelta, 
        bool _long,
        uint _markPrice
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[_indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(_indexToken);
        setUserUtility(_user);

        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position storage position = positions[_key];

        validateLastUpdateTime(position.lastUpdateTime);
        validate(position.size >= _sizeDelta, 18);

        uint _margin = position.size - position.collateral; 
        position.collateral -= 
        collectOperatingFee(_indexToken, _sizeDelta, _long, false) + collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(_user, _indexToken, _long); 
        _hasProfit ? position.collateral += _delta : position.collateral -= _delta;

        if(_long && _markPrice > position.entryPrice || !_long && position.entryPrice > _markPrice){
            _hasProfit = true;
        } else {
            _hasProfit = false;
        }

        _decreasePosition(
            _user, 
            _indexToken,
            _collateralDelta, 
            _sizeDelta,
            _markPrice,
            _margin,
            _long,
            _hasProfit
        );
        
        if(position.size > 0){
            validateLeverage(position.size, position.collateral, _user);
            validateLiquidatable(_user, _indexToken, _long, false);
        }

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function withdrawCollateral(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external onlyHandler(marketRouter) {   
        validate(whitelistedToken[_indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(_indexToken);

        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position storage position = positions[_key];

        validateLastUpdateTime(position.lastUpdateTime);
    
        uint _borrowFee = collectBorrowFee(_key); 

        (uint _delta, bool _hasProfit) = collectFundingFee(_user, _indexToken, _long); 
        _hasProfit ? position.collateral += _delta : position.collateral -= _delta;

        validate(position.collateral >= _collateralDelta + _borrowFee, 19);
        uint _collateralNext = position.collateral - _collateralDelta - _borrowFee; 
        uint _margin = position.collateral - _collateralNext; 
        
        borrowMargin(_key, _margin); 

        position.collateral = _collateralNext; 
        position.lastUpdateTime = block.timestamp;

        _collateralDelta = _collateralDelta.precisionToStable();
        IERC20(stable).safeTransfer(_user, _collateralDelta);
        
        validateLeverage(position.size, position.collateral, _user);
        validateLiquidatable(_user, _indexToken, _long, false);
        useLiquidity();
    }

    function serviceWithdrawCollateral(
        address _user, 
        address _indexToken, 
        bool _long
    ) external onlyHandler(marketRouter) {
        validate(!whitelistedToken[_indexToken], 0);
        updateTotalBorrows();

        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
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
            IERC20(stable).safeTransfer(_user, _collateralDelta);
        }

        delete positions[_key];
        useLiquidity();
    }

    function liquidatePosition(
        address _user,  
        address _indexToken,
        uint _sizeDelta,
        bool _long, 
        address _feeReceiver
    ) external onlyHandler(VAMM) {
        validate(whitelistedToken[_indexToken], 0);
        updateTotalBorrows();
        updateTotalFunding(_indexToken);
        setUserUtility(_user);

        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position memory position = positions[_key];

        uint _collateral = position.collateral; 
        uint _margin = _sizeDelta - _collateral;  
        uint _remainingLiquidationFee = liquidationFee; 
        uint _fee = preCalculateUserDebt(_key) - _margin;  

        _collateral > _remainingLiquidationFee ? _collateral -= _remainingLiquidationFee : _collateral = 0; 

        if(_fee >= _collateral){
            _margin += _fee - _collateral; 
            collectBorrowFee(_key);
            _collateral = 0;
        } else {
            _collateral -= collectBorrowFee(_key); 
            _fee = calculateOperationFeeAmount(_indexToken, _sizeDelta, _long, false); 
            if(_fee >= _collateral){
                poolAmount += _collateral;
                _collateral = 0;
            } else {
                _collateral -= collectOperatingFee(_indexToken, _sizeDelta, _long, false); 
                bool _hasProfit;
                (_fee, _hasProfit, , ) = preCalculateUserFundingFee(_user, _indexToken, _long);
                
                if(!_hasProfit && _fee > _collateral){
                    poolAmount += _collateral;
                    _collateral = 0;
                } else {
                    if(!_hasProfit && _collateral >= _fee){
                        collectFundingFee(_user, _indexToken, _long); 
                        _collateral -= _fee;
                    } else {
                        collectFundingFee(_user, _indexToken, _long); 
                        _collateral += _fee;
                    }
                }

                _remainingLiquidationFee = _collateral * remainingLiquidationFee / Math.PRECISION; 
                _collateral -= _remainingLiquidationFee; 
                _remainingLiquidationFee += liquidationFee; 
            }
        }

        borrowMarginRedeem(_key, _margin);
        fundingFeeRedeem(_key, _indexToken, _sizeDelta, _long);
    
        if(_collateral > 0) poolAmount += _collateral;

        _remainingLiquidationFee = _remainingLiquidationFee.precisionToStable();
        IERC20(stable).safeTransfer(_feeReceiver, _remainingLiquidationFee);

        delete positions[_key];

        if(zeroOperatingFee) utilityDecreaseOperationFee(false);
        useLiquidity();
    }

    function validateLiquidate(
        address _user, 
        address _indexToken, 
        bool _long
    ) public view returns(uint liquidatePrice, bool liquidatable) {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position memory position = positions[_key];

        if(position.size == 0) return (0, false); 

        (uint _collateral, uint _markPrice) = (position.collateral, IVAMM(VAMM).getPrice(_indexToken));
        (uint _fees, uint _delta) = calculateFees(_user, _indexToken, _long);

        if(_collateral + _delta > _fees){
            _collateral = _collateral + _delta - _fees; 
        } else {
            return (_markPrice, true);
        }

        uint _deviationToLiquidate = Math.PRECISION * Math.PRECISION / (position.size * Math.PRECISION  / _collateral); 
        
        liquidatePrice = _long ? 
        (Math.PRECISION * position.entryPrice - position.entryPrice * _deviationToLiquidate) / Math.PRECISION : 
        position.entryPrice * (Math.PRECISION + _deviationToLiquidate) / Math.PRECISION;

        liquidatable = _long ? liquidatePrice >= _markPrice : _markPrice >= liquidatePrice;
    }

    function preCalculatePositionDelta( 
        address _user, 
        address _indexToken, 
        bool _long
    ) public view returns(bool hasProfit, uint delta) {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position memory position = positions[_key];
        if(position.size == 0) return (false, 0);
        
        (uint _markPrice, uint _entryPrice) = (IVAMM(VAMM).getPrice(_indexToken), position.entryPrice);
        (uint _fees, uint _delta) = calculateFees(_user, _indexToken, _long);

        delta = position.size * getPriceDelta(_entryPrice, _markPrice) / _entryPrice;
        hasProfit = _long ? _markPrice > _entryPrice : _entryPrice > _markPrice;
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
        address _indexToken, 
        uint _sizeDelta, 
        bool _long, 
        bool _increase
    ) public view returns(uint) {
        return _sizeDelta * calculateOperatingFee(_indexToken, _long, _increase) / Math.PRECISION;
    }

    function calculateOperatingFee(address _indexToken, bool _long, bool _increase) public view returns(uint) {
        if(zeroOperatingFee) return 0;
        uint _vammPrice = IVAMM(VAMM).getPrice(_indexToken);
        uint _feedPrice = IPriceFeed(priceFeed).getPrice(_indexToken);
        uint _priceDelta = getPriceDelta(_vammPrice, _feedPrice) * Math.PRECISION / _vammPrice;
        if(_vammPrice > _feedPrice){
            if(_increase && _long || !_increase && !_long) return calculateOperatingFeeInternal(_priceDelta);
        }
        if(_vammPrice < _feedPrice){
            if(_increase && !_long || !_increase && _long) return calculateOperatingFeeInternal(_priceDelta);
        }
        return baseOperatingFee;
    }

    function validateLiquidatable(address _user, address _indexToken, bool _long, bool _bool) public view {
        (, bool _liquidatable) = validateLiquidate(_user, _indexToken, _long);
        validate(_liquidatable == _bool, 22);
    }

    function getPosition(
        address _user, 
        address _indexToken, 
        bool _long
    ) public view returns(uint, uint, uint, uint, bool, uint) {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position memory position = positions[_key];
        (bool _hasProfit, uint _delta) = preCalculatePositionDelta(_user, _indexToken, _long);
        return (
            position.collateral, 
            position.size, 
            position.entryPrice,  
            position.lastUpdateTime,
            _hasProfit,
            _delta
        );
    }

    function calculateOperatingFeeInternal(uint _priceDelta) internal view returns(uint) {
        return _priceDelta >= maxOperatingFeePriceDeviation ? 
        MAX_BASE_OPERATING_FEE + baseOperatingFee : 
        _priceDelta * operatingFeePriceMultiplier / Math.PRECISION + baseOperatingFee; 
    }

    function calculateFees(
        address _user, 
        address _indexToken, 
        bool _long
    ) internal view returns(uint fees, uint delta) {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position memory position = positions[_key];
        fees = preCalculateUserBorrowDebt(_key);

        (bool _staker, , bool _operatingFee, , , ) = IUtilityStorage(utilityStorage).getUserUtility(_user);
        if(!_staker || !_operatingFee) fees += calculateOperationFeeAmount(_indexToken, position.size, _long, false);

        bool _hasProfit;
        (delta, _hasProfit, ,) = preCalculateUserFundingFee(_user, _indexToken, _long);

        (fees, delta) = calculateFeesAndDelta(_hasProfit, fees, delta);
    }

    function collectOperatingFee(
        address _indexToken, 
        uint _sizeDelta, 
        bool _long, 
        bool _increase
    ) internal returns(uint operatingFeeAmount) {
        operatingFeeAmount = calculateOperationFeeAmount(_indexToken, _sizeDelta, _long, _increase);
        poolAmount += operatingFeeAmount;
    }

    function setUserUtility(address _user) internal {
        (bool _staker, , bool _operatingFee, , , ) = IUtilityStorage(utilityStorage).getUserUtility(_user);
        if(_staker && _operatingFee) utilityDecreaseOperationFee(true);
    }

    function utilityDecreaseOperationFee(bool _zeroFee) internal {
        zeroOperatingFee = _zeroFee;
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
        address _user, 
        address _indexToken,
        uint _collateralDelta, 
        uint _sizeDelta,
        uint _markPrice,
        uint _margin,
        bool _long,
        bool _hasProfit
    ) internal {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Position storage position = positions[_key];
        _collateralDelta = position.size == _sizeDelta ? position.collateral : _collateralDelta; 
        validate(position.collateral >= _collateralDelta, 29);
        
        uint _priceDelta = getPriceDelta(position.entryPrice, _markPrice);
        uint _sizeNext = position.size - _sizeDelta; 
        uint _realizedPnL = (position.size * _priceDelta / position.entryPrice) - (_sizeNext * _priceDelta / position.entryPrice); 
        uint _collateralNext = position.collateral - _collateralDelta; 
        uint _marginNext = _sizeNext - _collateralNext; 

        if(!_hasProfit) validate(_collateralDelta >= _realizedPnL, 30);

        if(_marginNext > _margin){
            _margin = _marginNext - _margin;
            borrowMargin(_key, _margin); 
        } else {
            _margin = _margin - _marginNext; 
            borrowMarginRedeem(_key, _margin);
        }

        if(_sizeNext > position.size){
            _margin = _sizeNext - position.size;
            getEntryFunding(_key, _indexToken, _margin, _long);
        } else {
            _margin = position.size - _sizeNext;
            fundingFeeRedeem(_key, _indexToken, _margin, _long);
        }

        if(_sizeNext > 0){
            position.size = _sizeNext; 
            position.collateral = _collateralNext; 
            position.lastUpdateTime = block.timestamp;
        } else {
            delete positions[_key];
        }
        
        // margin = income {stack too deep prevent}
        _margin = _hasProfit ? _collateralDelta + _realizedPnL : _collateralDelta - _realizedPnL; 
        _hasProfit ? poolAmount -= _realizedPnL : poolAmount += _realizedPnL;

        if(_hasProfit || _margin > 0){
            _margin = _margin.precisionToStable();
            IERC20(stable).safeTransfer(_user, _margin);
        }
    }
}