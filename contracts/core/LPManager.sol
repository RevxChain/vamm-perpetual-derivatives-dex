// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./interfaces/IPositionsTracker.sol";
import "../libraries/Governable.sol";
import "./interfaces/IVault.sol";
import "../libraries/Math.sol";

contract LPManager is ERC20Burnable, Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public constant MAX_BASE_PROVIDER_FEE = 100;
    uint public constant MAX_PROFIT_PROVIDER_FEE = 200;
    
    uint public baseProviderFee;
    uint public profitProviderFee;
    uint public feeReserves;

    address public vault;
    address public stable;
    address public positionsTracker;

    bool public isInitialized;

    constructor() ERC20("Vault Supply Token", "sToken") {}

    function initialize(
        address _vault, 
        address _stable,
        address _positionsTracker
    ) external onlyHandler(gov) {  
        require(!isInitialized, "LPManager: initialized");
        isInitialized = true;

        vault = _vault;
        stable = _stable;
        positionsTracker = _positionsTracker;

        baseProviderFee = 50;
        profitProviderFee = 100;
    }

    function setBaseProviderFee(uint _baseProviderFee) external onlyHandler(dao) {
        require(MAX_BASE_PROVIDER_FEE >= _baseProviderFee, "LPManager: ");
        baseProviderFee = _baseProviderFee;
    }

    function setProfitProviderFee(uint _profitProviderFee) external onlyHandler(dao) {
        require(MAX_PROFIT_PROVIDER_FEE >= _profitProviderFee, "LPManager: ");
        profitProviderFee = _profitProviderFee;
    }

    function addLiquidity(uint _underlyingAmount) external nonReentrant() {
        validateAmount(_underlyingAmount);
       
        _underlyingAmount = collectFees(_underlyingAmount);
        uint _amount = _underlyingAmount.stableToPrecision();

        uint _userShare; 
        if(totalSupply() > 0){
            _userShare = _amount * totalSupply() / IVault(vault).poolAmount();
        } else {
            _userShare = _amount.sqrt();
            _mint(vault, Math.INIT_LOCK_AMOUNT);
        }
        _mint(msg.sender, _userShare);

        IVault(vault).increasePool(_amount);
        IERC20(stable).safeTransferFrom(msg.sender, vault, _underlyingAmount);
    }

    function removeLiquidity(uint _sTokenAmount) external nonReentrant() {
        validateAmount(_sTokenAmount);
        uint _underlyingAmount = calculateUnderlying(_sTokenAmount);

        _burn(msg.sender, _sTokenAmount);
 
        IVault(vault).decreasePool(msg.sender, _underlyingAmount.stableToPrecision(), _underlyingAmount);
    }

    function calculateUnderlying(uint _sTokenAmount) public view returns(uint underlyingAmount) {
        uint _stableAmount = _sTokenAmount * IVault(vault).poolAmount() / totalSupply();
        underlyingAmount = _stableAmount.precisionToStable();
    }

    function decimals() public override pure returns(uint8) {
        return 9;
    }
    
    function collectFees(uint _amount) internal returns(uint) {
        (bool _isActual, bool _hasProfit, uint _totalDelta) = IPositionsTracker(positionsTracker).getPositionsData();
        uint _baseFee = baseProviderFee;
        uint _profitFee;
        if(_isActual){
            if(_hasProfit){
                _baseFee = _totalDelta / 10 > _baseFee ? 0 : _baseFee;
            } else {
                _profitFee = _totalDelta / 10 > _profitFee ? MAX_PROFIT_PROVIDER_FEE : profitProviderFee;
            }
        }

        uint _feeAmount = _amount * (_baseFee + _profitFee) / Math.PRECISION;
        if(_feeAmount == 0) return _amount;
        feeReserves += _feeAmount;
        uint afterFeeAmount = _amount - _feeAmount;
        IERC20(stable).safeTransferFrom(msg.sender, address(this), _feeAmount);

        return afterFeeAmount;
    }

    function validateAmount(uint _amount) internal pure {
        require(_amount > 0, "LPManager: invalid amount");
    }
}