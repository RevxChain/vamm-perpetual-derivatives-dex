// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./FundingModule.sol";

import "../periphery/interfaces/IDebtor.sol";

contract FlashLoanModule is FundingModule, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public constant LOCAL_DENOMINATOR = 1e8;
    uint public constant MIN_LOAN_FEE = 1000;
    uint public constant MAX_LOAN_FEE = 2000000;

    uint public baseLoanFee;
    uint public minAmountToLoan;
    uint public protocolFeeReserves;

    bool public flashLoanEnabled;

    function setMinAmountToLoan(uint newMinAmountToLoan) external onlyHandlers() {
        validate(newMinAmountToLoan > 0, 33);
        minAmountToLoan = newMinAmountToLoan;
    }

    function setFlashLoanEnabled(bool enable) external onlyHandlers() {
        flashLoanEnabled = enable;
    }

    function setBaseLoanFee(uint newBaseLoanFee) external onlyHandler(dao) {
        validate(newBaseLoanFee >= MIN_LOAN_FEE, 34);
        validate(MAX_LOAN_FEE >= newBaseLoanFee, 35);
        baseLoanFee = newBaseLoanFee;
    }

    function withdrawProtocolFees() external onlyHandler(gov) nonReentrant() {
        IERC20(stable).safeTransfer(msg.sender, protocolFeeReserves);
        protocolFeeReserves = 0;
    }
    
    function withdrawFees() external onlyHandler(controller) nonReentrant() {
        IERC20(stable).safeTransfer(msg.sender, feeReserves.precisionToStable());
        feeReserves = 0;
    }

    function flashLoan(uint amount, bytes calldata data) external nonReentrant() returns(uint fee, uint income) {
        address _debtor = msg.sender;
        validate(flashLoanEnabled, 36);
        validate(amount >= minAmountToLoan, 37);
        validate(_debtor != tx.origin, 38);
        validate(poolAmount >= amount, 39);
        uint _balanceBefore = IERC20(stable).balanceOf(address(this));
        validate(_balanceBefore >= amount, 40);

        uint _fee = calculateFlashLoanFee(amount, tx.origin);
        fee = calculateFlashLoanFee(amount, _debtor);
        fee = fee > _fee ? _fee : fee;

        (uint _poolBefore, uint _borrowsBefore, uint _borrowPoolBefore) = (poolAmount, totalBorrows, borrowPool);

        IERC20(stable).safeTransfer(_debtor, amount);
        IDebtor(_debtor).executeFlashLoan(amount, fee, data);
        IERC20(stable).safeTransferFrom(_debtor, address(this), amount + fee);

        uint _balanceAfter = IERC20(stable).balanceOf(address(this));
        (uint _poolAfter, uint _borrowsAfter, uint _borrowPoolAfter) = (poolAmount, totalBorrows, borrowPool);

        validate(_balanceAfter >= _balanceBefore + fee, 41);
        validate(_poolAfter == _poolBefore, 42);
        validate(_borrowsAfter == _borrowsBefore, 43);
        validate(_borrowPoolAfter == _borrowPoolBefore, 44);

        income = _balanceAfter - _balanceBefore;   
        protocolFeeReserves += income;
    }

    function calculateFlashLoanFee(uint amount, address user) public view returns(uint fee) {
        uint _loanFee = baseLoanFee;

        (bool _staker, , , , , uint _flashLoanFee) = IUtilityStorage(utilityStorage).getUserUtility(user);
        if(_staker && _flashLoanFee > 0) _loanFee /= _flashLoanFee;

        fee = amount.mulDiv(_loanFee, LOCAL_DENOMINATOR);
    }
}