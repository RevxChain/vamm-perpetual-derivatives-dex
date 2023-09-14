// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IUtilityStorage {

    function utilityToken() external view returns(address);
    function marketRouter() external view returns(address);

    function owners(address _user) external view returns(uint tokenId);

    function deposit(uint _tokenId, uint _lockDuration) external;

    function withdraw(uint _tokenId, address _receiver) external;

    function getUserUtility(address _user) external view returns(
        bool staker, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    );
    
}