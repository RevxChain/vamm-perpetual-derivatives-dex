// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./VaultBase.sol";

contract BorrowingModule is VaultBase {
    
    uint public constant MAX_BASE_BORROW_RATE_PER_YEAR = 5e16; 
    uint public constant MAX_EXTRA_BORROW_RATE_PER_YEAR = 10e16; 
    
    uint public feeReserves;
    uint public borrowPool; 
    uint public totalBorrows;
    uint public lastUpdateTotalBorrows; 
    uint public utilizationRateKink;
    uint public baseBorrowRatePerYear;
    uint public extraBorrowRatePerYear;

    function setBaseBorrowRatePerYear(uint _baseBorrowRatePerYear) external onlyHandler(dao) {
        validate(MAX_BASE_BORROW_RATE_PER_YEAR >= _baseBorrowRatePerYear, 9);
        validate(extraBorrowRatePerYear >= _baseBorrowRatePerYear, 10);
        baseBorrowRatePerYear = _baseBorrowRatePerYear;
    }

    function setExtraBorrowRatePerYear(uint _extraBorrowRatePerYear) external onlyHandler(dao) {
        validate(MAX_EXTRA_BORROW_RATE_PER_YEAR >= _extraBorrowRatePerYear, 11);
        validate(_extraBorrowRatePerYear >= baseBorrowRatePerYear, 12);
        extraBorrowRatePerYear = _extraBorrowRatePerYear;
    }

    function setUtilizationRateKink(uint _utilizationRateKink) external onlyHandler(dao) {
        validate(Math.PRECISION >= _utilizationRateKink, 13);
        utilizationRateKink = _utilizationRateKink;
    } 

    function updateTotalBorrows() public returns(uint) {
        if(block.timestamp - lastUpdateTotalBorrows > 0){
            totalBorrows = preUpdateTotalBorrows();
            lastUpdateTotalBorrows = block.timestamp;
        }
        return totalBorrows;
    }

    function preUpdateTotalBorrows() public view returns(uint) {
        if(block.timestamp - lastUpdateTotalBorrows > 0){
            return totalBorrows + calculatePoolIncrease(totalBorrows, calculateActualBorrowRate(), lastUpdateTotalBorrows);
        } else {
            return totalBorrows;
        }       
    }

    function preCalculateUserDebt(bytes32 _key) public view returns(uint) {
        return positions[_key].borrowed * preUpdateTotalBorrows() / borrowPool;
    }

    function preCalculateUserBorrowDebt(bytes32 _key) public view returns(uint) {
        Position memory position = positions[_key];
        uint _margin = position.size - position.collateral;
        return preCalculateUserDebt(_key) > _margin ? preCalculateUserDebt(_key) - _margin : 0;
    }

    function availableLiquidity() public view returns(uint) {
        return poolAmount > preUpdateTotalBorrows() ? poolAmount - preUpdateTotalBorrows() : 0;
    }

    function calculateActualBorrowRate() public view returns(uint) {
        if(utilizationRateKink > utilizationRate()){
            if(utilizationRate() >= Math.DENOMINATOR){
                return extraBorrowRatePerYear;
            } else {
                return baseBorrowRatePerYear;
            } 
        } else {
            return extraBorrowRatePerYear * utilizationRate() / Math.DENOMINATOR;
        }
    }

    function utilizationRate() public view returns(uint) {
        return preUpdateTotalBorrows() * Math.PRECISION / poolAmount;
    }

    function borrowMargin(bytes32 _key, uint _margin) internal {
        validate(availableLiquidity() >= _margin, 25);
        uint _userShares = _margin * borrowPool / totalBorrows;
        positions[_key].borrowed += _userShares;
        borrowPool += _userShares;
        totalBorrows += _margin;  
    }

    function collectBorrowFee(bytes32 _key) internal returns(uint userBorrowDebt) {
        userBorrowDebt = preCalculateUserBorrowDebt(_key);
        if(userBorrowDebt > 0){
            uint _halfBorrowDebt = userBorrowDebt / 2;
            uint _sharePoolDecrease = userBorrowDebt * borrowPool / totalBorrows;
            positions[_key].borrowed -= _sharePoolDecrease; 
            borrowPool -= _sharePoolDecrease;
            totalBorrows -= userBorrowDebt;
            poolAmount += _halfBorrowDebt;
            feeReserves += userBorrowDebt - _halfBorrowDebt;
        }
    }

    function borrowMarginRedeem(bytes32 _key, uint _margin) internal {
        uint _sharePoolDecrease = _margin * borrowPool / totalBorrows;
        Position storage position = positions[_key];
        if(shouldValidatePoolShares) validatePoolShares(totalBorrows, _margin, borrowPool, _sharePoolDecrease, position.borrowed);
        _sharePoolDecrease >= position.borrowed ? 
        position.borrowed = 0 : position.borrowed -= _sharePoolDecrease;
        _sharePoolDecrease >= borrowPool ? 
        borrowPool = Math.INIT_LOCK_AMOUNT : borrowPool -= _sharePoolDecrease;
        _margin >= totalBorrows ? 
        totalBorrows = Math.INIT_LOCK_AMOUNT : totalBorrows -= _margin;
    }
}