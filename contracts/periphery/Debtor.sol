// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../core/interfaces/IVault.sol";
import "./interfaces/IDebtor.sol";

contract Debtor is IDebtor, Ownable {
    using SafeERC20 for IERC20;

    uint public balance;
    uint public amount;
    uint public fee;

    address public immutable stable;
    address public immutable vault;

    bool locked;

    constructor(address _vault) {
        vault = _vault;
        stable = IVault(_vault).stable();
    }

    receive() external payable {}

    function loan(uint _amount, bytes calldata _data) external payable onlyOwner() {
        require(!locked, "Debtor: locked");
        (locked, amount, balance, fee) = (true, _amount, IERC20(stable).balanceOf(address(this)), calculateActualFee(_amount));

        IVault(vault).flashLoan(_amount, _data);

        (locked, amount, balance, fee) = (false, 0, 0, 0);
    }

    function executeFlashLoan(uint _amount, uint _fee, bytes calldata /*_data*/) external {
        require(tx.origin == owner(), "Debtor: invalid tx sender");
        require(msg.sender == vault, "Debtor: invalid msg sender");
        require(amount == _amount, "Debtor: wrong amount");
        require(fee == _fee, "Debtor: wrong fee");
        require(locked, "Debtor: should locked");
        require(IERC20(stable).balanceOf(address(this)) >= balance + _amount, "Debtor: invalid input balance");

        // logic

        require(IERC20(stable).balanceOf(address(this)) >= _amount + _fee, "Debtor: invalid output balance");
        IERC20(stable).approve(vault, _amount + _fee);
    }

    function withdraw(address _token, uint _amount, address payable _receiver) external onlyOwner() {
        _token != address(0) ? IERC20(_token).safeTransfer(_receiver, _amount) : safeTransfer(_receiver, _amount);
    }

    function calculateActualFee(uint _amount) public view returns(uint) {
        return IVault(vault).calculateFlashLoanFee(_amount, owner());
    }

    function safeTransfer(address payable _receiver, uint _value) internal {
        (bool _success, ) = _receiver.call{value: _value}(new bytes(0));
        require(_success, "Debtor: ETH transfer failed");
    }
}

