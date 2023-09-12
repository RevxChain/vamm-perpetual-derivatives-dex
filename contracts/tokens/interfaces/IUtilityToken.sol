// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IUtilityToken is IERC721 {

    function totalTypes() external view returns(uint);
    function typeId(uint _tokenId) external view returns(uint);

    function mint(address[] calldata _user, uint[] calldata _typeId) external;

    function setTypeData( 
        string calldata _grade, 
        uint _maxTotalSupply, 
        uint _maxLeverage, 
        uint _operatingFee, 
        bool _liquidator, 
        uint _votePower
    ) external;

    function updateTypeData(
        uint _typeId,  
        uint _maxLeverage, 
        uint _operatingFee, 
        bool _liquidator, 
        uint _votePower
    ) external;

}