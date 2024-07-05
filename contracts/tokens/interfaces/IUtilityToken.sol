// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IUtilityToken is IERC721 {

    function totalTypes() external view returns(uint);
    function typeId(uint tokenId) external view returns(uint);

    function mint(address[] calldata user, uint[] calldata typeId) external;

    function getUtility(uint tokenId) external view returns(
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    );

    function setTypeData( 
        string calldata grade, 
        uint maxTotalSupply, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    ) external;

    function updateTypeData(
        uint typeId,  
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    ) external;

}