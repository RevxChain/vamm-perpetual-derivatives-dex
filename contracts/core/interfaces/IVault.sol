// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVault {

    function VAMM() external view returns(address);
    function LPManager() external view returns(address);
    function stable() external view returns(address);
    function priceFeed() external view returns(address);
    function positionsTracker() external view returns(address);
    function marketRouter() external view returns(address);
    function utilityStorage() external view returns(address);

    function poolAmount() external view returns(uint);
    function minChangeTime() external view returns(uint);
    function baseMaxLeverage() external view returns(uint);
    function liquidationFee() external view returns(uint);
    function remainingLiquidationFee() external view returns(uint);
    function borrowPool() external view returns(uint);
    function totalBorrows() external view returns(uint);
    function feeReserves() external view returns(uint); 
    function protocolFeeReserves() external view returns(uint);
    function lastUpdateTotalBorrows() external view returns(uint);
    function utilizationRateKink() external view returns(uint);
    function baseBorrowRatePerYear() external view returns(uint);
    function extraBorrowRatePerYear() external view returns(uint);
    function fundingPriceMultiplier() external view returns(uint);
    function baseOperatingFee() external view returns(uint);
    function maxOperatingFeePriceDeviation() external view returns(uint);
    function operatingFeePriceMultiplier() external view returns(uint);
    function minAmountToLoan() external view returns(uint);
    function baseLoanFee() external view returns(uint);

    function shouldValidatePoolShares() external view returns(bool);
    function flashLoanEnabled() external view returns(bool);

    function whitelistedToken(address _indexToken) external view returns(bool);
    function errors(uint _errorCode) external view returns(string memory);
    function calculatePositionKey(address _user, address _indexToken, bool _long) external pure returns(bytes32);
    function preUpdateTotalBorrows() external view returns(uint);
    function preCalculateUserDebt(bytes32 _key) external view returns(uint);
    function preCalculateUserBorrowDebt(bytes32 _key) external view returns(uint);
    function availableLiquidity() external view returns(uint);
    function calculateActualBorrowRate() external view returns(uint);
    function utilizationRate() external view returns(uint);
    function preUpdateTotalFunding(address _indexToken) external view returns(uint, uint);
    function calculateOperatingFee(address _indexToken, bool _long, bool _increase) external view returns(uint);
    function validateLiquidatable(address _user, address _indexToken, bool _long, bool _bool) external view;
    function calculateFlashLoanFee(uint _amount, address _user) external view returns(uint fee);

    function preCalculateUserFundingFee(
        address _user, 
        address _indexToken, 
        bool _long
    ) external view returns(
        uint delta, 
        bool hasProfit, 
        uint fundingFeeDebt, 
        uint fundingFeeGain
    );

    function validateLiquidate(
        address _user, 
        address _indexToken, 
        bool _long
    ) external view returns(uint liquidatePrice, bool liquidatable);

    function preCalculatePositionDelta( 
        address _user, 
        address _indexToken, 
        bool _long
    ) external view returns(bool hasProfit, uint delta);

    function calculateOperationFeeAmount( 
        address _indexToken, 
        uint _sizeDelta, 
        bool _long, 
        bool _increase
    ) external view returns(uint);

    function getPosition(
        address _user, 
        address _indexToken, 
        bool _long
    ) external view returns(
        uint collateral, 
        uint size, 
        uint entryPrice, 
        uint lastUpdateTime, 
        bool hasProfit, 
        uint delta
    );

    function setBaseMaxLeverage(uint _baseMaxLeverage) external;
    function setLiquidationFee(uint _liquidationFee) external;
    function setRemainingLiquidationFee(uint _remainingLiquidationFee) external;
    function setMinChangeTime(uint _minChangeTime) external;
    function setPoolSharesValidation(bool _shouldValidatePoolShares) external;
    function setError(uint _errorCode, string calldata _error) external;
    function setBaseBorrowRatePerYear(uint _baseBorrowRatePerYear) external;
    function setExtraBorrowRatePerYear(uint _extraBorrowRatePerYear) external;
    function setUtilizationRateKink(uint _utilizationRateKink) external;
    function setFundingPriceMultiplier(uint _fundingPriceMultiplier) external;
    function setTokenConfig(address _indexToken) external;
    function deleteTokenConfig(address _indexToken) external;
    function setBaseOperatingFee(uint _baseOperatingFee) external;
    function setMaxOperatingFeePriceDeviation(uint _maxOperatingFeePriceDeviation) external;
    function setOperatingFeePriceMultiplier(uint _operatingFeePriceMultiplier) external;
    function setMinAmountToLoan(uint _minAmountToLoan) external;
    function setBaseLoanFee(uint _baseFee) external;
    function setFlashLoanEnabled(bool _enabled) external;
    function withdrawProtocolFees() external;
    function withdrawFees() external;

    function flashLoan(uint _amount, bytes calldata _data) external returns(uint fee, uint income);

    function updateTotalBorrows() external returns(uint);

    function updateTotalFunding(address _indexToken) external returns(uint, uint);

    function increasePool(uint _amount) external;

    function decreasePool(
        address _user, 
        uint _amount, 
        uint _underlyingAmount
    ) external;

    function directIncreasePool(uint _underlyingAmount) external;

    function increasePosition(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta, 
        bool _long, 
        uint _markPrice 
    ) external;

    function addCollateral(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external;

    function decreasePosition(
        address _user, 
        address _indexToken, 
        uint _collateralDelta,  
        uint _sizeDelta, 
        bool _long,
        uint _markPrice
    ) external;

    function withdrawCollateral(
        address _user, 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external;

    function serviceWithdrawCollateral(
        address _user, 
        address _indexToken, 
        bool _long
    ) external;

    function liquidatePosition(
        address _user,  
        address _indexToken,
        uint _sizeDelta,
        bool _long, 
        address _feeReceiver
    ) external;

}