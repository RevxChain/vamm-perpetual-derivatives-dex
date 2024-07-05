// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../core/interfaces/IVault.sol";
import "./interfaces/IDebtor.sol";

contract Debtor is IDebtor, Ownable {
    using SafeERC20 for IERC20;

    uint public sBalance;
    uint public sAmount;
    uint public sFee;

    address public immutable stable;
    address public immutable vault;

    bool locked;

    constructor(address _vault) {
        vault = _vault;
        stable = IVault(_vault).stable();
    }

    receive() external payable {}

    function loan(uint amount, bytes calldata data) external payable onlyOwner() {
        require(!locked, "Debtor: locked");
        (locked, sAmount, sBalance, sFee) = (true, amount, IERC20(stable).balanceOf(address(this)), calculateActualFee(amount));

        IVault(vault).flashLoan(amount, data);

        (locked, sAmount, sBalance, sFee) = (false, 0, 0, 0);
    }

    function executeFlashLoan(uint amount, uint fee, bytes calldata /*data*/) external {
        require(tx.origin == owner(), "Debtor: invalid tx sender");
        require(msg.sender == vault, "Debtor: invalid msg sender");
        require(sAmount == amount, "Debtor: wrong amount");
        require(sFee == fee, "Debtor: wrong fee");
        require(locked, "Debtor: should locked");
        require(IERC20(stable).balanceOf(address(this)) >= sBalance + amount, "Debtor: invalid input balance");

        // logic

        require(IERC20(stable).balanceOf(address(this)) >= amount + fee, "Debtor: invalid output balance");
        IERC20(stable).approve(vault, amount + fee);
    }

    function withdraw(address token, uint amount, address payable receiver) external onlyOwner() {
        token != address(0) ? IERC20(token).safeTransfer(receiver, amount) : safeTransfer(receiver, amount);
    }

    function calculateActualFee(uint amount) public view returns(uint) {
        return IVault(vault).calculateFlashLoanFee(amount, owner());
    }

    function safeTransfer(address payable receiver, uint value) internal {
        (bool _success, ) = receiver.call{value: value}(new bytes(0));
        require(_success, "Debtor: ETH transfer failed");
    }
}

