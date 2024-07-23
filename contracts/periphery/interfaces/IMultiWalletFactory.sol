// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMultiWalletFactory {

    function totalWallets() external view returns(uint);

    function stable() external view returns(address);
    function lpManager() external view returns(address);
    function orderBook() external view returns(address);
    function marketRouter() external view returns(address);
    function vault() external view returns(address); 
    function multiWalletMarketplace() external view returns(address);

    function wallets(uint index) external view returns(address);
    function walletExist(address multiWallet) external view returns(bool);

    function createMultiWallet(address owner) external returns(address newMultiWallet);

    function getWalletOwner(address multiWalletAddress) external view returns(bool multiWalletExist, address currentOwner, address pendingOwner);
    
}