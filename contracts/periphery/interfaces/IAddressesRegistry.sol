// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IAddressesRegistry {
    
    function stable() external view returns(address);
    function vault() external view returns(address);
    function LPManager() external view returns(address);
    function marketRouter() external view returns(address);
    function orderBook() external view returns(address);
    function positionsTracker() external view returns(address);
    function liquidityManagerProxy() external view returns(address);
    function VAMM() external view returns(address);
    function priceFeed() external view returns(address);
    function fastPriceFeed() external view returns(address);
    function multiWalletFactory() external view returns(address);
    function multiWalletMarketplace() external view returns(address);
    function LPStaking() external view returns(address);
    function stakedSupplyToken() external view returns(address);
    function govToken() external view returns(address);
    function utilityToken() external view returns(address);
    function utilityStorage() external view returns(address);
    function liquidityManagerImplementation() external view returns(address);
    function getActualGovAddress(address target) external view returns(address);
    function getActualDaoAddress(address target) external view returns(address);
    function getActualControllerAddress(address target) external view returns(address);

}