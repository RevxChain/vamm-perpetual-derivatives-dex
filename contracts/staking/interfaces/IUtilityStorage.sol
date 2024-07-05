// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IUtilityStorage {

    function utilityToken() external view returns(address);
    function marketRouter() external view returns(address);

    function owners(address user) external view returns(uint tokenId);

    function deposit(uint tokenId, uint lockDuration) external;

    function withdraw(uint tokenId, address receiver) external;

    function getUserUtility(address user) external view returns(
        bool staker, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    );
    
}