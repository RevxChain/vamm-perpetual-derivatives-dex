// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IVAMM.sol";

contract MarketRouter is Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;
    
    uint public constant MIN_POSITION_WORTH = 10e18;

    address public vault;
    address public VAMM;
    address public stable;
    address public utilityStorage;

    bool public liquidatePrivateMode;
    bool public isInitialized;

    mapping(address => bool) public liquidators;
    mapping(address => bool) public liquidatorsUtility;
    mapping(address => bool) public whitelistedToken;

    modifier whitelisted(address indexToken, bool include) {
        require(whitelistedToken[indexToken] == include, "MarketRouter: invalid whitelisted");
        _;
    }

    modifier onlyLiquidator() {
        if(liquidatePrivateMode) 
        require(liquidators[msg.sender] || liquidatorsUtility[msg.sender], "MarketRouter: invalid handler");
        _;
    }

    function initialize(
        address _vault,
        address _VAMM,
        address _stable,
        address _controller,
        address _utilityStorage
    ) external onlyHandler(gov) validateAddress(_controller) {  
        require(!isInitialized, "MarketRouter: initialized");
        isInitialized = true;

        vault = _vault;
        VAMM = _VAMM;
        stable = _stable;
        controller = _controller;
        utilityStorage = _utilityStorage;

        liquidatePrivateMode = true;
    }

    function setTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, false) {   
        whitelistedToken[indexToken] = true;
    }

    function deleteTokenConfig(address indexToken) external onlyHandler(controller) whitelisted(indexToken, true) {   
        whitelistedToken[indexToken] = false;
    }

    function setLiquidator(address liquidator, bool set) external onlyHandlers() {
        liquidators[liquidator] = set;
    }

    function setLiquidatorUtility(address liquidator, bool set) external onlyHandler(utilityStorage) {
        liquidatorsUtility[liquidator] = set;
    }

    function setLiquidatePrivateMode(bool set) external onlyHandler(dao) {
        liquidatePrivateMode = set;
    }

    function increasePosition( 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta,
        bool long
    ) external nonReentrant() whitelisted(indexToken, true) {
        address _user = msg.sender; 
        (uint _currentCollateral, , , , ,) = IVault(vault).getPosition(_user, indexToken, long);
        if(_currentCollateral == 0) require(collateralDelta >= MIN_POSITION_WORTH, "MarketRouter: insufficient collateral");

        IVault(vault).validateLiquidatable(_user, indexToken, long, false);
        validateDelta(sizeDelta, collateralDelta);

        if(collateralDelta > 0) IERC20(stable).safeTransferFrom(_user, vault, collateralDelta.precisionToStable());

        IVAMM(VAMM).updateIndex(
            _user,
            indexToken, 
            collateralDelta, 
            sizeDelta, 
            long,
            true,
            false,
            address(0)
        );
    }

    function addCollateral( 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external nonReentrant() whitelisted(indexToken, true) {  
        address _user = msg.sender;  
        IVault(vault).validateLiquidatable(_user, indexToken, long, false);  
        validateDelta(collateralDelta, collateralDelta);  

        IERC20(stable).safeTransferFrom(_user, vault, collateralDelta.precisionToStable());

        IVault(vault).addCollateral(_user, indexToken, collateralDelta, long);
    }

    function withdrawCollateral( 
        address indexToken, 
        uint collateralDelta, 
        bool long
    ) external nonReentrant() whitelisted(indexToken, true) { 
        address _user = msg.sender;  
        IVault(vault).validateLiquidatable(_user, indexToken, long, false); 
        validateDelta(collateralDelta, collateralDelta);
        IVault(vault).withdrawCollateral(_user, indexToken, collateralDelta, long);
    }

    function serviceWithdrawCollateral(
        address user, 
        address indexToken, 
        bool long
    ) external nonReentrant() whitelisted(indexToken, false) {
        IVault(vault).serviceWithdrawCollateral(user, indexToken, long);
    }

    function decreasePosition( 
        address indexToken, 
        uint collateralDelta, 
        uint sizeDelta,
        bool long
    ) external nonReentrant() whitelisted(indexToken, true) { 
        address _user = msg.sender;     
        IVault(vault).validateLiquidatable(_user, indexToken, long, false);
        validateDelta(sizeDelta, collateralDelta);

        IVAMM(VAMM).updateIndex(
            _user,
            indexToken, 
            collateralDelta, 
            sizeDelta, 
            long,
            false,
            false,
            address(0)
        );
    }

    function liquidatePosition(
        address user,
        address indexToken,
        bool long,
        address feeReceiver
    ) external onlyLiquidator() nonReentrant() whitelisted(indexToken, true) {
        IVault(vault).validateLiquidatable(user, indexToken, long, true);

        (, uint _sizeDelta, , , ,) = IVault(vault).getPosition(user, indexToken, long);

        IVAMM(VAMM).updateIndex(
            user, 
            indexToken,  
            0,
            _sizeDelta,
            long,
            false,
            true,
            feeReceiver
        );
    }

    function validateDelta(uint sizeDelta, uint collateralDelta) internal pure {
        require(sizeDelta > 0 || collateralDelta > 0, "MarketRouter: invalid delta");
    }
}