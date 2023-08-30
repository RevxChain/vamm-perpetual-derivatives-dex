// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IVAMM.sol";
import "./interfaces/IVault.sol";
import "../libraries/Governable.sol";
import "../libraries/Math.sol";

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

    modifier whitelisted(address _indexToken, bool _include) {
        require(whitelistedToken[_indexToken] == _include, "MarketRouter: invalid whitelisted");
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
    }

    function setTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, false) {   
        whitelistedToken[_indexToken] = true;
    }

    function deleteTokenConfig(address _indexToken) external onlyHandler(controller) whitelisted(_indexToken, true) {   
        whitelistedToken[_indexToken] = false;
    }

    function setLiquidator(address _liquidator, bool _bool) external onlyHandlers() {
        liquidators[_liquidator] = _bool;
    }

    function setLiquidatorUtility(address _liquidator, bool _bool) external onlyHandler(utilityStorage) {
        liquidatorsUtility[_liquidator] = _bool;
    }

    function setLiquidatePrivateMode(bool _bool) external onlyHandler(dao) {
        liquidatePrivateMode = _bool;
    }

    function increasePosition( 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta,
        bool _long
    ) external nonReentrant() whitelisted(_indexToken, true) {    
        require(_collateralDelta >= MIN_POSITION_WORTH, "MarketRouter: insufficient collateral");
        address _user = msg.sender;  
        IVault(vault).validateLiquidatable(_user, _indexToken, _long, false);
        validateDelta(_sizeDelta, _collateralDelta);
        if(_collateralDelta > 0) IERC20(stable).safeTransferFrom(_user, vault, _collateralDelta.precisionToStable());

        IVAMM(VAMM).updateIndex(
            _user,
            _indexToken, 
            _collateralDelta, 
            _sizeDelta, 
            _long,
            true,
            false,
            address(0)
        );
    }

    function addCollateral( 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external nonReentrant() whitelisted(_indexToken, true) {  
        address _user = msg.sender;  
        IVault(vault).validateLiquidatable(_user, _indexToken, _long, false);  
        validateDelta(_collateralDelta, _collateralDelta);  

        IERC20(stable).safeTransferFrom(_user, vault, _collateralDelta.precisionToStable());

        IVault(vault).addCollateral(_user, _indexToken, _collateralDelta, _long);
    }

    function withdrawCollateral( 
        address _indexToken, 
        uint _collateralDelta, 
        bool _long
    ) external nonReentrant() whitelisted(_indexToken, true) { 
        address _user = msg.sender;  
        IVault(vault).validateLiquidatable(_user, _indexToken, _long, false); 
        validateDelta(_collateralDelta, _collateralDelta);
        IVault(vault).withdrawCollateral(_user, _indexToken, _collateralDelta, _long);
    }

    function serviceWithdrawCollateral(
        address _user, 
        address _indexToken, 
        bool _long
    ) external nonReentrant() whitelisted(_indexToken, false) {

        IVault(vault).serviceWithdrawCollateral(_user, _indexToken, _long);
    }

    function decreasePosition( 
        address _indexToken, 
        uint _collateralDelta, 
        uint _sizeDelta,
        bool _long
    ) external nonReentrant() whitelisted(_indexToken, true) { 
        address _user = msg.sender;     
        IVault(vault).validateLiquidatable(_user, _indexToken, _long, false);
        validateDelta(_sizeDelta, _collateralDelta);

        IVAMM(VAMM).updateIndex(
            _user,
            _indexToken, 
            _collateralDelta, 
            _sizeDelta, 
            _long,
            false,
            false,
            address(0)
        );
    }

    function liquidatePosition(
        address _user,
        address _indexToken,
        bool _long,
        address _feeReceiver
    ) external onlyLiquidator() nonReentrant() whitelisted(_indexToken, true) {
        IVault(vault).validateLiquidatable(_user, _indexToken, _long, true);

        (, uint _sizeDelta, , , ,) = IVault(vault).getPosition(_user, _indexToken, _long);

        IVAMM(VAMM).updateIndex(
            _user, 
            _indexToken,  
            0,
            _sizeDelta,
            _long,
            false,
            true,
            _feeReceiver
        );
    }

    function validateDelta(uint _sizeDelta, uint _collateralDelta) internal pure {
        require(_sizeDelta > 0 || _collateralDelta > 0, "MarketRouter: invalid delta");
    }
}