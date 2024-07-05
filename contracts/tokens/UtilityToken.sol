// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "../libraries/Governable.sol";

contract UtilityToken is ERC721Enumerable, Governable, ReentrancyGuard {

    uint public constant TOTAL_TYPES = 3;
    uint public constant MAX_TOTAL_SUPPLY = 3000;
    uint public constant ONE_YEAR = 52 weeks;

    uint public totalTypes;

    string private __baseURI;

    bool public isInitialized;

    mapping(uint => Utility) public utilities;
    mapping(uint => uint) public typeId;

    struct Utility {
        string grade;
        uint totalSupply;
        uint maxTotalSupply;
        uint maxLeverage;
        bool operatingFee;
        bool liquidator;
        uint votePower;
        uint flashLoanFee;
        uint lastUpdated;
    }

    constructor() ERC721("UtilityToken", "Utility") {}

    function initialize(
        address _controller, 
        string calldata baseURI_
    ) external onlyHandler(gov) validateAddress(_controller) {   
        require(!isInitialized, "UtilityToken: initialized");
        isInitialized = true;

        controller = _controller;
        __baseURI = baseURI_;
    }

    function mint(address[] calldata user, uint[] calldata typeID) external onlyHandler(gov) {
        require(user.length == typeID.length, "UtilityToken: invalid data array length");
        require(MAX_TOTAL_SUPPLY >= totalSupply() + user.length, "UtilityToken: global max total supply exhausted");
        for(uint i; user.length > i; i++){
            _mintInternal(user[i], typeID[i]);
        }
    }

    function setInitTypeData( 
        string calldata grade, 
        uint maxTotalSupply, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    ) external onlyHandler(gov) {
        require(TOTAL_TYPES > totalTypes, "UtilityToken: total types exceeded");
        utilities[totalTypes] = Utility({
            grade: grade,
            totalSupply: 0,
            maxTotalSupply: maxTotalSupply,
            maxLeverage: maxLeverage,
            operatingFee: operatingFee,
            liquidator: liquidator,
            votePower: votePower,
            flashLoanFee: flashLoanFee,
            lastUpdated: block.timestamp
        });

        totalTypes += 1;
    }

    function updateTypeData(
        uint typeID,  
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    ) external onlyHandler(dao) {
        Utility storage utility = utilities[typeID];
        require(totalTypes > typeID, "UtilityToken: invalid type Id");
        require(block.timestamp >= utility.lastUpdated + ONE_YEAR, "UtilityToken: too soon to update");
        utility.maxLeverage = maxLeverage;
        utility.operatingFee =operatingFee;
        utility.liquidator = liquidator;
        utility.votePower = votePower;
        utility.flashLoanFee = flashLoanFee;
        utility.lastUpdated = block.timestamp;
    }

    function getUtility(uint tokenId) external view returns(uint, bool, bool, uint, uint) {
        uint _typeId = typeId[tokenId];
        Utility memory utility = utilities[_typeId];
        return (
            utility.maxLeverage, 
            utility.operatingFee, 
            utility.liquidator, 
            utility.votePower, 
            utility.flashLoanFee
        );
    }

    function _mintInternal(address user, uint typeID) internal {
        Utility storage utility = utilities[typeID];
        require(utility.maxTotalSupply > utility.totalSupply, "UtilityToken: type Id max total supply exhausted");
        utility.totalSupply += 1;
        typeId[totalSupply()] = typeID;
        _safeMint(user, totalSupply());
    }

    function _baseURI() internal view override returns(string memory) {
        return __baseURI;
    }
}