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

    function mint(address[] calldata _user, uint[] calldata _typeId) external onlyHandler(controller) {
        require(_user.length == _typeId.length, "UtilityToken: invalid data array length");
        require(MAX_TOTAL_SUPPLY >= totalSupply() + _user.length, "UtilityToken: global max total supply exhausted");
        for(uint i; _user.length > i; i++){
            _mintInternal(_user[i], _typeId[i]);
        }
    }

    function setInitTypeData( 
        string calldata _grade, 
        uint _maxTotalSupply, 
        uint _maxLeverage, 
        bool _operatingFee, 
        bool _liquidator, 
        uint _votePower,
        uint _flashLoanFee
    ) external onlyHandler(gov) {
        require(TOTAL_TYPES > totalTypes, "UtilityToken: total types exceeded");
        utilities[totalTypes] = Utility({
            grade: _grade,
            totalSupply: 0,
            maxTotalSupply: _maxTotalSupply,
            maxLeverage: _maxLeverage,
            operatingFee: _operatingFee,
            liquidator: _liquidator,
            votePower: _votePower,
            flashLoanFee: _flashLoanFee,
            lastUpdated: block.timestamp
        });

        totalTypes += 1;
    }

    function updateTypeData(
        uint _typeId,  
        uint _maxLeverage, 
        bool _operatingFee, 
        bool _liquidator, 
        uint _votePower,
        uint _flashLoanFee
    ) external onlyHandler(dao) {
        Utility storage utility = utilities[_typeId];
        require(totalTypes > _typeId, "UtilityToken: invalid type Id");
        require(block.timestamp >= utility.lastUpdated + ONE_YEAR, "UtilityToken: too soon to update");
        utility.maxLeverage = _maxLeverage;
        utility.operatingFee =_operatingFee;
        utility.liquidator = _liquidator;
        utility.votePower = _votePower;
        utility.flashLoanFee = _flashLoanFee;
        utility.lastUpdated = block.timestamp;
    }

    function getUtility(uint _tokenId) external view returns(uint, bool, bool, uint, uint) {
        uint _typeId = typeId[_tokenId];
        Utility memory utility = utilities[_typeId];
        return (
            utility.maxLeverage, 
            utility.operatingFee, 
            utility.liquidator, 
            utility.votePower, 
            utility.flashLoanFee
        );
    }

    function _mintInternal(address _user, uint _typeId) internal {
        Utility storage utility = utilities[_typeId];
        require(utility.maxTotalSupply > utility.totalSupply, "UtilityToken: type Id max total supply exhausted");
        utility.totalSupply += 1;
        typeId[totalSupply()] = _typeId;
        _safeMint(_user, totalSupply());
    }

    function _baseURI() internal view override returns(string memory) {
        return __baseURI;
    }
}