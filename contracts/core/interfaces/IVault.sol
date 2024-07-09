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
    function liquidityManager() external view returns(address);
    
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
    function cappedBorrowRate() external view returns(bool); 
    function fundingPriceMultiplier() external view returns(uint);
    function baseOperatingFee() external view returns(uint);
    function maxOperatingFeePriceDeviation() external view returns(uint);
    function operatingFeePriceMultiplier() external view returns(uint);
    function minAmountToLoan() external view returns(uint);
    function baseLoanFee() external view returns(uint);

    function flashLoanEnabled() external view returns(bool);
    function shouldValidatePoolShares() external view returns(bool);
    function extraUsageLiquidityEnabled() external view returns(bool);
    
    function whitelistedToken(address indexToken) external view returns(bool);
    function errors(uint errorCode) external view returns(string memory);
    function calculatePositionKey(address user, address indexToken, bool long) external pure returns(bytes32);
    function preUpdateTotalBorrows() external view returns(uint);
    function preCalculateUserDebt(bytes32 key) external view returns(uint);
    function preCalculateUserBorrowDebt(bytes32 key) external view returns(uint);
    function availableLiquidity() external view returns(uint);
    function calculateActualBorrowRate() external view returns(uint);
    function utilizationRate() external view returns(uint rate);
    function preUpdateTotalFunding(address indexToken) external view returns(uint, uint);
    function calculateOperatingFee(address indexToken, bool long, bool increase) external view returns(uint);
    function validateLiquidatable(address user, address indexToken, bool long, bool condition) external view;
    function calculateFlashLoanFee(uint amount, address user) external view returns(uint fee);
    function positions(bytes32 key) external view returns(Position memory);

    struct Position {
        uint collateral;
        uint size;
        uint entryPrice;
        uint borrowed;  
        uint entryFunding;
        uint lastUpdateTime; 
    }

    function preCalculateUserFundingFee(
        address user, 
        address indexToken, 
        bool long
    ) external view returns(
        uint delta, 
        bool hasProfit, 
        uint fundingFeeDebt, 
        uint fundingFeeGain
    );

    function validateLiquidate(
        address user, 
        address indexToken, 
        bool long
    ) external view returns(uint liquidatePrice, bool liquidatable);

    function preCalculatePositionDelta( 
        address user, 
        address indexToken, 
        bool long
    ) external view returns(bool hasProfit, uint delta);

    function calculateOperationFeeAmount( 
        address indexToken, 
        uint sizeDelta, 
        bool long, 
        bool increase
    ) external view returns(uint);

    function getPosition(
        address user, 
        address indexToken, 
        bool long
    ) external view returns(
        uint collateral, 
        uint size, 
        uint entryPrice, 
        uint lastUpdateTime, 
        bool hasProfit, 
        uint delta
    );

    function setBaseMaxLeverage(uint newBaseMaxLeverage) external;
    function setLiquidationFee(uint newLiquidationFee) external;
    function setRemainingLiquidationFee(uint newRemainingLiquidationFee) external;
    function setMinChangeTime(uint newMinChangeTime) external;
    function setPoolSharesValidation(bool enableShouldValidatePoolShares) external;
    function setError(uint errorCode, string calldata errorMsg) external;
    function setBaseBorrowRatePerYear(uint newBaseBorrowRatePerYear) external;
    function setExtraBorrowRatePerYear(uint newExtraBorrowRatePerYear) external;
    function setUtilizationRateKink(uint newUtilizationRateKink) external;
    function setCappedBorrowRate(bool enableCappedBorrowRate) external;
    function setFundingPriceMultiplier(uint newFundingPriceMultiplier) external;
    function setTokenConfig(address indexToken) external;
    function deleteTokenConfig(address indexToken) external;
    function setBaseOperatingFee(uint newBaseOperatingFee) external;
    function setMaxOperatingFeePriceDeviation(uint newMaxOperatingFeePriceDeviation) external;
    function setOperatingFeePriceMultiplier(uint newOperatingFeePriceMultiplier) external;
    function setMinAmountToLoan(uint newMinAmountToLoan) external;
    function setBaseLoanFee(uint newBaseLoanFee) external;
    function setFlashLoanEnabled(bool enable) external;
    function setExtraUsageLiquidityEnabled(bool enableExtraUsageLiquidity) external;
    function withdrawProtocolFees() external;
    function withdrawFees() external;

    function flashLoan(uint amount, bytes calldata data) external returns(uint fee, uint income);

    function updateTotalBorrows() external returns(uint);

    function updateTotalFunding(address indexToken) external returns(uint, uint);

    function increasePool(uint amount) external;

    function decreasePool(address user, uint amount, uint underlyingAmount) external;

    function directIncreasePool(uint underlyingAmount) external;

    function manualUseLiquidity() external;

    function increasePosition(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta, 
        bool long, 
        uint markPrice 
    ) external;

    function addCollateral(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external;

    function decreasePosition(
        address user, 
        address indexToken, 
        uint collateralDelta,  
        uint sizeDelta, 
        bool long,
        uint markPrice
    ) external;

    function withdrawCollateral(
        address user, 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external;

    function serviceWithdrawCollateral(
        address user, 
        address indexToken, 
        bool long
    ) external;

    function liquidatePosition(
        address user,  
        address indexToken,
        uint sizeDelta,
        bool long, 
        address feeReceiver
    ) external;

}