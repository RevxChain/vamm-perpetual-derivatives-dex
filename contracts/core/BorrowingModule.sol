// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./VaultBase.sol";

contract BorrowingModule is VaultBase {
    using Math for uint;
    
    uint public constant MAX_BASE_BORROW_RATE_PER_YEAR = 5e16; 
    uint public constant MAX_EXTRA_BORROW_RATE_PER_YEAR = 10e16; 
    
    uint public feeReserves;
    uint public borrowPool; 
    uint public totalBorrows;
    uint public lastUpdateTotalBorrows; 
    uint public utilizationRateKink;
    uint public baseBorrowRatePerYear;
    uint public extraBorrowRatePerYear;

    function setBaseBorrowRatePerYear(uint newBaseBorrowRatePerYear) external onlyHandler(dao) {
        validate(MAX_BASE_BORROW_RATE_PER_YEAR >= newBaseBorrowRatePerYear, 9);
        validate(extraBorrowRatePerYear >= newBaseBorrowRatePerYear, 10);
        baseBorrowRatePerYear = newBaseBorrowRatePerYear;
    }

    function setExtraBorrowRatePerYear(uint newExtraBorrowRatePerYear) external onlyHandler(dao) {
        validate(MAX_EXTRA_BORROW_RATE_PER_YEAR >= newExtraBorrowRatePerYear, 11);
        validate(newExtraBorrowRatePerYear >= baseBorrowRatePerYear, 12);
        extraBorrowRatePerYear = newExtraBorrowRatePerYear;
    }

    function setUtilizationRateKink(uint newUtilizationRateKink) external onlyHandler(dao) {
        validate(Math.PRECISION >= newUtilizationRateKink, 13);
        utilizationRateKink = newUtilizationRateKink;
    } 

    function updateTotalBorrows() public returns(uint) {
        if(block.timestamp > lastUpdateTotalBorrows){
            totalBorrows = preUpdateTotalBorrows();
            lastUpdateTotalBorrows = block.timestamp;
        }
        return totalBorrows;
    }

    function preUpdateTotalBorrows() public view returns(uint) {
        if(block.timestamp > lastUpdateTotalBorrows){
            return totalBorrows + calculatePoolIncrease(totalBorrows, calculateActualBorrowRate(), lastUpdateTotalBorrows);
        } else {
            return totalBorrows;
        }       
    }

    function preCalculateUserDebt(bytes32 key) public view returns(uint) { 
        return positions[key].borrowed.mulDiv(preUpdateTotalBorrows(), borrowPool);
    }

    function preCalculateUserBorrowDebt(bytes32 key) public view returns(uint) {
        Position memory position = positions[key];
        uint _margin = position.size - position.collateral;
        return preCalculateUserDebt(key) > _margin ? preCalculateUserDebt(key) - _margin : 0;
    }

    function availableLiquidity() public view returns(uint) {
        return poolAmount > preUpdateTotalBorrows() ? poolAmount - preUpdateTotalBorrows() : 0;
    }

    function calculateActualBorrowRate() public view returns(uint) {
        if(utilizationRateKink > utilizationRate()){
            return utilizationRate() >= Math.DENOMINATOR ? extraBorrowRatePerYear : baseBorrowRatePerYear;
        } else {
            return extraBorrowRatePerYear * utilizationRate() / Math.DENOMINATOR;
        }
    }

    function utilizationRate() public view returns(uint) {
        return preUpdateTotalBorrows().mulDiv(Math.PRECISION, poolAmount);
    }

    function borrowMargin(bytes32 key, uint margin) internal {
        validate(availableLiquidity() >= margin, 25);
        uint _userShares = margin.mulDiv(borrowPool, totalBorrows);
        positions[key].borrowed += _userShares;
        borrowPool += _userShares;
        totalBorrows += margin;  
    }

    function collectBorrowFee(bytes32 key) internal returns(uint userBorrowDebt) {
        userBorrowDebt = preCalculateUserBorrowDebt(key);
        if(userBorrowDebt > 0){
            uint _halfBorrowDebt = userBorrowDebt / 2;
            uint _sharePoolDecrease = userBorrowDebt.mulDiv(borrowPool, totalBorrows);
            positions[key].borrowed -= _sharePoolDecrease; 
            borrowPool -= _sharePoolDecrease;
            totalBorrows -= userBorrowDebt;
            poolAmount += _halfBorrowDebt;
            feeReserves += userBorrowDebt - _halfBorrowDebt;
        }
    }

    function borrowMarginRedeem(bytes32 key, uint margin) internal {
        uint _sharePoolDecrease = margin.mulDiv(borrowPool, totalBorrows);
        Position storage position = positions[key];
        if(shouldValidatePoolShares) validatePoolShares(totalBorrows, margin, borrowPool, _sharePoolDecrease, position.borrowed);

        _sharePoolDecrease >= position.borrowed ? 
        position.borrowed = 0 : position.borrowed -= _sharePoolDecrease;

        _sharePoolDecrease >= borrowPool ? 
        borrowPool = Math.INIT_LOCK_AMOUNT : borrowPool -= _sharePoolDecrease;
        
        margin >= totalBorrows ? 
        totalBorrows = Math.INIT_LOCK_AMOUNT : totalBorrows -= margin;
    }
}