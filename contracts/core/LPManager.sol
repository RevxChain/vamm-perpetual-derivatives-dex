// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "./interfaces/IPositionsTracker.sol";
import "./interfaces/IVault.sol";

contract LPManager is ERC20Burnable, Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;

    uint public constant MAX_BASE_REMOVE_FEE = 50;
    uint public constant MAX_BASE_PROVIDER_FEE = 100;
    uint public constant MAX_PROFIT_PROVIDER_FEE = 150;
    uint public constant MAX_LOCK_DURATION = 1 days;
    
    uint public baseRemoveFee;
    uint public baseProviderFee;
    uint public profitProviderFee;
    uint public feeReserves;
    uint public lockDuration;

    address public vault;
    address public stable;
    address public positionsTracker;

    bool public isInitialized;

    mapping(address => uint) public lastAdded;

    constructor() ERC20("Vault Supply Token", "sToken") {}

    function initialize(
        address _vault, 
        address _stable,
        address _positionsTracker,
        address _controller
    ) external onlyHandler(gov) {  
        require(!isInitialized, "LPManager: initialized");
        isInitialized = true;

        vault = _vault;
        stable = _stable;
        positionsTracker = _positionsTracker;
        controller = _controller;

        baseRemoveFee = 20;
        baseProviderFee = 40;
        profitProviderFee = 80;
        lockDuration = 10 minutes;
    }

    function setBaseRemoveFee(uint newBaseRemoveFee) external onlyHandler(dao) {
        require(MAX_BASE_REMOVE_FEE >= newBaseRemoveFee, "LPManager: invalid baseRemoveFee");
        baseRemoveFee = newBaseRemoveFee;
    }

    function setBaseProviderFee(uint newBaseProviderFee) external onlyHandler(dao) {
        require(MAX_BASE_PROVIDER_FEE >= newBaseProviderFee, "LPManager: invalid baseProviderFee");
        baseProviderFee = newBaseProviderFee;
    }

    function setProfitProviderFee(uint newProfitProviderFee) external onlyHandler(dao) {
        require(MAX_PROFIT_PROVIDER_FEE >= newProfitProviderFee, "LPManager: invalid profitProviderFee");
        profitProviderFee = newProfitProviderFee;
    }

    function setLockDuration(uint newLockDuration) external onlyHandler(dao) {
        require(MAX_LOCK_DURATION >= newLockDuration, "LPManager: invalid lockDuration");
        lockDuration = newLockDuration;
    }

    function withdrawFees() external onlyHandler(controller) {
        IERC20(stable).safeTransfer(msg.sender, feeReserves);
        feeReserves = 0;
    }

    function addLiquidity(uint underlyingAmount) external nonReentrant() returns(uint lpAmount) {
        validateAmount(underlyingAmount);
        underlyingAmount = collectAddFees(underlyingAmount);
        (uint _amount, address _user)= (underlyingAmount.stableToPrecision(), msg.sender);
 
        if(totalSupply() > 0){
            lpAmount = _amount.mulDiv(totalSupply(), IVault(vault).poolAmount());
        } else {
            lpAmount = _amount.sqrt();
            _mint(vault, Math.INIT_LOCK_AMOUNT);
        }
        
        _mint(_user, lpAmount);
        lastAdded[_user] = block.timestamp;
        IERC20(stable).safeTransferFrom(_user, vault, underlyingAmount);
        IVault(vault).increasePool(_amount);
    }

    function removeLiquidity(uint sTokenAmount) external nonReentrant() returns(uint underlyingAmount) {
        address _user = msg.sender;
        require(block.timestamp >= lastAdded[_user] + lockDuration, "LPManager: liquidity locked");
        validateAmount(sTokenAmount);

        underlyingAmount = collectRemoveFees(calculateUnderlying(sTokenAmount));

        _burn(_user, sTokenAmount);
 
        IVault(vault).decreasePool(_user, underlyingAmount.stableToPrecision(), underlyingAmount);
    }

    function calculateUnderlying(uint sTokenAmount) public view returns(uint underlyingAmount) {
        uint _stableAmount = sTokenAmount.mulDiv(IVault(vault).poolAmount(), totalSupply());
        underlyingAmount = _stableAmount.precisionToStable();
    }

    function decimals() public pure override returns(uint8) {
        return 9;
    }
    
    function collectAddFees(uint amount) internal returns(uint) {
        if(msg.sender == controller) return amount;
        (bool _isActual, bool _hasProfit, uint _totalDelta) = IPositionsTracker(positionsTracker).getPositionsData();
        (uint _baseFee, uint _profitFee) = (baseProviderFee, 0);
        if(_isActual){
            if(_hasProfit){
                _baseFee = _totalDelta / 10 > _baseFee ? 0 : _baseFee;
            } else {
                _profitFee = _totalDelta / 10 > _profitFee ? MAX_PROFIT_PROVIDER_FEE : profitProviderFee;
            }
        }

        uint _feeAmount = amount.mulDiv((_baseFee + _profitFee), Math.PRECISION);
        
        if(IVault(vault).totalBorrows() > IVault(vault).availableLiquidity() || _feeAmount == 0) return amount;

        feeReserves += _feeAmount;
        uint _afterFeeAmount = amount - _feeAmount;
        IERC20(stable).safeTransferFrom(msg.sender, address(this), _feeAmount);

        return _afterFeeAmount;
    }

    function collectRemoveFees(uint amount) internal returns(uint) {
        (bool _isActual, bool _hasProfit, uint _totalDelta) = IPositionsTracker(positionsTracker).getPositionsData();
        (uint _baseFee, uint _profitFee, uint _removeFee) = (baseProviderFee, baseRemoveFee, 0);
        if(_isActual){
            if(_hasProfit){
                _baseFee = _totalDelta / 10 > MAX_PROFIT_PROVIDER_FEE ? _baseFee : MAX_PROFIT_PROVIDER_FEE;
            } else {
                _profitFee = _totalDelta / 10 > _profitFee ? 0 : profitProviderFee;
            }
        }

        if(IVault(vault).totalBorrows() > IVault(vault).availableLiquidity()) _removeFee = baseRemoveFee;

        uint _feeAmount = amount.mulDiv((_baseFee + _profitFee + _removeFee), Math.PRECISION);
        if(_feeAmount == 0) return amount;

        feeReserves += _feeAmount;
        uint _afterFeeAmount = amount - _feeAmount;
        IVault(vault).decreasePool(address(this), _feeAmount.stableToPrecision(), _feeAmount);

        return _afterFeeAmount;
    }

    function validateAmount(uint amount) internal pure {
        require(amount > 0, "LPManager: invalid amount");
    }
}