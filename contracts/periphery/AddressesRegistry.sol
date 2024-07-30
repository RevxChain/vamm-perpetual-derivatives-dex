// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/interfaces/IGovernable.sol";

contract AddressesRegistry {

    address public stable;
    address public vault;
    address public LPManager;
    address public marketRouter;
    address public orderBook;
    address public positionsTracker;
    address public liquidityManagerProxy;
    address public VAMM;
    address public priceFeed;
    address public fastPriceFeed;
    address public multiWalletFactory;
    address public multiWalletMarketplace;
    address public LPStaking;
    address public stakedSupplyToken;
    address public govToken;
    address public utilityToken;
    address public utilityStorage;

    function liquidityManagerImplementation() external view returns(address) {
        (, bytes memory _response) = liquidityManagerProxy.staticcall(abi.encodeWithSignature("implementation()"));
        return abi.decode(_response, (address));
    }

    function getActualGovAddress(address target) external view returns(address) {
        return IGovernable(target).gov();
    }

    function getActualDaoAddress(address target) external view returns(address) {
        return IGovernable(target).dao();
    }

    function getActualControllerAddress(address target) external view returns(address) {
        return IGovernable(target).controller();
    }

}