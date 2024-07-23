// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMultiWalletMarketplace {

    function baseSellFee() external view returns(uint);
    function multiWalletFactory() external view returns(address);

    function sellFee(address paymentToken) external view returns(uint);
    function orders(address multiWallet) external view returns(Order memory);

    struct Order {
        address paymentToken;
        uint price;
        address paymentReceiver;
        uint deadline;
        address purchaser;
        address receiver;
        uint creationTime;
    }

    function setBaseSellFee(uint newBaseSellFee) external;

    function setSellFee(address paymentToken, uint newSellFee) external;

    function withdraw(address token, uint amount, address payable receiver) external;

    function createOrder(
        address paymentToken,
        uint price,
        address paymentReceiver,
        uint deadline
    ) external returns(bool result);

    function cancelOrder() external returns(bool result);

    function purchaseMultiWallet(
        address multiWallet, 
        uint expectedCreationTime,
        address receiver
    ) external payable returns(bool result);

    function setNewReceiver(address multiWallet, address receiver) external returns(bool result);

    function getFeeAmount(address paymentToken, uint amount) external view returns(uint feeAmount, uint afterFeeAmount);
    
}