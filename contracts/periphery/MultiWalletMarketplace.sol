// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IMultiWalletFactory.sol";
import "./interfaces/IOwnable2Step.sol";

contract MultiWalletMarketplace is Governable {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public baseSellFee;

    address public multiWalletFactory;

    bool public isInitialized;

    mapping(address => uint) public sellFee;
    mapping(address => Order) public orders;

    struct Order {
        address paymentToken;
        uint price;
        address paymentReceiver;
        uint deadline;
        address purchaser; 
        address receiver;
        uint creationTime;
    }

    function initialize(address _multiWalletFactory) external onlyHandler(gov) {   
        require(!isInitialized, "MultiWalletMarketplace: initialized");
        isInitialized = true;

        multiWalletFactory = _multiWalletFactory;
        baseSellFee = 100;
        sellFee[address(0)] = 10;
    }

    function setBaseSellFee(uint newBaseSellFee) external onlyHandlers() {
        require(Math.PRECISION >= newBaseSellFee, "MultiWalletMarketplace: invalid fee value");
        baseSellFee = newBaseSellFee;
    }

    function setSellFee(address paymentToken, uint newSellFee) external onlyHandlers() {
        require(Math.PRECISION >= newSellFee, "MultiWalletMarketplace: invalid fee value");
        sellFee[paymentToken] = newSellFee;
    }

    function withdraw(address token, uint amount, address payable receiver) external onlyHandler(dao) {
        token != address(0) ? IERC20(token).safeTransfer(receiver, amount) : _safeETHTransfer(receiver, amount);
    }

    function createOrder(
        address paymentToken,
        uint price,
        address paymentReceiver,
        uint deadline
    ) external returns(bool result) {
        require(price > 0, "MultiWalletMarketplace: zero price");
        require(paymentReceiver != address(0), "MultiWalletMarketplace: receiver zero address");
        if(deadline > 0) require(deadline > block.timestamp, "MultiWalletMarketplace: invalid deadline");

        address _multiWallet = msg.sender;
        (bool _multiWalletExist, , address _pendingOwner) = _getOwnerData(_multiWallet);

        require(_multiWalletExist, "MultiWalletMarketplace: non-existent wallet");
        require(orders[_multiWallet].purchaser == address(0), "MultiWalletMarketplace: order already purchased");
        require(_pendingOwner == address(this), "MultiWalletMarketplace: invalid pending owner");
        
        orders[_multiWallet] = Order({
            paymentToken: paymentToken,
            price: price,
            paymentReceiver: paymentReceiver,
            deadline: deadline,
            purchaser: address(0),
            receiver: address(0),
            creationTime: block.timestamp
        });

        return true;
    }

    function cancelOrder() external returns(bool result) {
        address _multiWallet = msg.sender;
        (, address _currentOwner, address _pendingOwner) = _getOwnerData(_multiWallet);

        Order memory order = orders[_multiWallet];

        if(_pendingOwner == address(this)){
            require(order.purchaser == address(0), "MultiWalletMarketplace: order already purchased");
        } else {
            require(
                _currentOwner == order.purchaser || _currentOwner == order.receiver, 
                "MultiWalletMarketplace: invalid current owner"
            );
        }

        delete orders[_multiWallet];

        return true;
    }

    function purchaseMultiWallet(
        address multiWallet, 
        uint expectedCreationTime, 
        address receiver
    ) external payable returns(bool result) {
        address _buyer = msg.sender;
        Order memory order = orders[multiWallet];

        _orderExistCheck(order.price);
        
        require(order.creationTime == expectedCreationTime, "MultiWalletMarketplace: frontrun abuse");

        require(order.purchaser == address(0), "MultiWalletMarketplace: order already purchased");
        if(order.deadline > 0) require(order.deadline >= block.timestamp, "MultiWalletMarketplace: expired");

        orders[multiWallet].purchaser = _buyer;

        IOwnable2Step(multiWallet).acceptOwnership();

        require(IOwnable2Step(multiWallet).pendingOwner() == address(0), "MultiWalletMarketplace: access error");
        require(IOwnable2Step(multiWallet).owner() == address(this), "MultiWalletMarketplace: access error");

        // _feeAmount for event
        (uint _feeAmount, uint _afterFeeAmount) = getFeeAmount(order.paymentToken, order.price);

        if(order.paymentToken == address(0)) {
            require(msg.value == order.price, "MultiWalletMarketplace: invalid msg value");
            _safeETHTransfer(payable(order.paymentReceiver), _afterFeeAmount);
        } else {
            uint _balanceBefore = IERC20(order.paymentToken).balanceOf(address(this));
            IERC20(order.paymentToken).safeTransferFrom(_buyer, address(this), order.price);
            require(
                IERC20(order.paymentToken).balanceOf(address(this)) >= _balanceBefore + order.price, 
                "MultiWalletMarketplace: transfer failed"
            );
            IERC20(order.paymentToken).safeTransfer(order.paymentReceiver, _afterFeeAmount);
        }

        if(receiver == address(0)) receiver = _buyer;

        _setNewReceiver(multiWallet, receiver);

        return true;
    }

    function setNewReceiver(address multiWallet, address receiver) external returns(bool result) {
        require(
            msg.sender == orders[multiWallet].purchaser || 
            msg.sender == orders[multiWallet].receiver, 
            "MultiWalletMarketplace: access error"
        );

        _setNewReceiver(multiWallet, receiver);

        return true;
    }

    function getFeeAmount(address paymentToken, uint amount) public view returns(uint feeAmount, uint afterFeeAmount) {
        uint _fee = sellFee[paymentToken];
        if(_fee == 0) _fee = baseSellFee;
        if(_fee == 0) return (0, amount);
        feeAmount = amount.mulDiv(_fee, Math.PRECISION);
        afterFeeAmount = amount - feeAmount;
    }

    function _safeETHTransfer(address payable receiver, uint value) internal {
        (bool _success, ) = receiver.call{value: value}("");
        require(_success, "MultiWalletMarketplace: ETH transfer failed");
    }

    function _setNewReceiver(address multiWallet, address newReceiver) internal {
        require(newReceiver != address(this), "MultiWalletMarketplace: invalid receiver address");

        orders[multiWallet].receiver = newReceiver;
        IOwnable2Step(multiWallet).transferOwnership(newReceiver);
        require(IOwnable2Step(multiWallet).pendingOwner() == newReceiver, "MultiWalletMarketplace: access error");
    }

    function _getOwnerData(
        address multiWallet
    ) internal view returns(bool multiWalletExist, address currentOwner, address pendingOwner) {
        (multiWalletExist, currentOwner, pendingOwner) = IMultiWalletFactory(multiWalletFactory).getWalletOwner(multiWallet);
    }

    function _orderExistCheck(uint price) internal pure {
        require(price > 0, "MultiWalletMarketplace: non-existent order");
    }

}