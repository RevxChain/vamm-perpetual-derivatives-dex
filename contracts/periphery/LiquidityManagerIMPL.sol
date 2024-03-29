// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

import "../core/interfaces/IPositionsTracker.sol";
import "../libraries/ImplementationSlot.sol";
import "../core/interfaces/IVault.sol";
import "../libraries/Governable.sol";
import "../libraries/Math.sol";

contract LiquidityManagerIMPL is ImplementationSlot, Governable, ReentrancyGuard  {
    using SafeERC20 for IERC20;   
    using Math for uint;

    uint public minRemoveAllowedShare;
    uint public initStableAmount;
    uint public aTokenAmount;
    uint public referralCode;

    address public aToken;
    address public targetPool;
    address public rewardsController;
    address public extraReward;
    
    bool public active;
    bool public newImplEnabled;

    Settings public addSlot;
    Settings public removeSlot;

    event Success(bytes response, uint time);
    event Failure(bytes response, uint time);

    struct Settings {
        uint allowedSupplyRate;
        uint allowedAmount;
        uint allowedShare;
        uint utilizationRateKink; 
        uint availableLiquidityKink;
        uint poolAmountKink;
        uint totalPositionsDeltaKink;
    }

    function initialize(
        address _vault,
        address _stable,
        address _positionsTracker,
        address _poolTarget,
        address _rewardsController,
        address _extraReward
    ) external {  
        require(!isInitialized, "LiquidityManager: initialized");
        isInitialized = true;

        gov = msg.sender;
        dao = msg.sender;
        vault = _vault;
        stable = _stable;
        positionsTracker = _positionsTracker;
        strategy = "AAVEv3 Pure Supply v1.0";

        targetPool = _poolTarget;
        aToken = IPool(_poolTarget).getReserveData(_stable).aTokenAddress;
        rewardsController = _rewardsController;
        extraReward = _extraReward;

        usageEnabled = true;
        manualUsageEnabled = true;
        totalPositionsConsider = true;
        minRemoveAllowedShare = 1000;
    }

    function setNewImplementation(address _implementation, string calldata _strategy) external onlyHandler(dao) {
        require(isInitialized, "LiquidityManager: not initialized");
        if(active){
            newImplEnabled = true;
            IVault(vault).manualUseLiquidity();
        }
        require(!active, "LiquidityManager: active");

        address[] memory _tokens = new address[](1);
        _tokens[0] = aToken;

        IRewardsController(rewardsController).claimRewards(_tokens, type(uint).max, gov, extraReward);
        
        delete addSlot;
        delete removeSlot;
        delete initStableAmount;
        delete aTokenAmount;
        delete referralCode;
        delete targetPool;
        delete aToken;
        delete usageEnabled;
        delete autoUsageEnabled;
        delete manualUsageEnabled;
        delete minRemoveAllowedShare;
        delete newImplEnabled;
        delete rewardsController;
        delete extraReward;

        strategy = _strategy;
        implementation = _implementation;
    }

    function setStrategySettings(
        Settings calldata _addSetup, 
        Settings calldata _removeSetup
    ) external onlyHandler(dao) {
        string memory _error = "LiquidityManager: invalid settings";
        require(isInitialized, "LiquidityManager: not initialized");
        require(!active, "LiquidityManager: active");
        require(targetPool != address(0), "LiquidityManager: main settings not initialized");
        require(_addSetup.allowedSupplyRate > _removeSetup.allowedSupplyRate, _error);
        require(_removeSetup.utilizationRateKink > _addSetup.utilizationRateKink, _error);
        require(_addSetup.availableLiquidityKink > _removeSetup.availableLiquidityKink, _error);
        require(_addSetup.poolAmountKink > _removeSetup.poolAmountKink, _error);
        require(_removeSetup.totalPositionsDeltaKink > _addSetup.totalPositionsDeltaKink, _error);
        require(Math.PRECISION >= _addSetup.allowedShare, _error);
        require(Math.PRECISION >= _removeSetup.allowedShare, _error);
        require(_removeSetup.allowedShare >= minRemoveAllowedShare, _error);
        addSlot = _addSetup;
        removeSlot = _removeSetup;
    }

    function setUsageEnabled(bool _enabled) external onlyHandler(dao) {
        require(!active, "LiquidityManager: active");
        usageEnabled = _enabled;
    }

    function setAutoUsageEnabled(bool _enabled) external onlyHandler(dao) {
        autoUsageEnabled = _enabled;
    }

    function setManualUsageEnabled(bool _enabled) external onlyHandler(dao) {
        manualUsageEnabled = _enabled;
    }

    function setTotalPositionsConsider(bool _consider) external onlyHandler(dao) {
        totalPositionsConsider = _consider;
    }

    function provideLiquidity(uint _amount) external onlyHandler(vault) nonReentrant() {
        Settings storage slot = addSlot;
        if(_amount > IERC20(stable).balanceOf(address(this))){
            IERC20(stable).safeTransfer(vault, IERC20(stable).balanceOf(address(this)));
            return;
        }
        
        if(slot.allowedAmount > _amount) slot.allowedAmount = _amount;
        
        IERC20(stable).approve(targetPool, _amount);
        (bool _success, bytes memory _response) = targetPool.call(
            abi.encodeWithSignature("supply(address,uint256,address,uint16)", stable, _amount, address(this), referralCode)
        ); 

        if(_success){
            active = true;
            initStableAmount = _amount;
            aTokenAmount = IERC20(aToken).balanceOf(address(this));

            emit Success(_response, block.timestamp);
        } else {
            IERC20(stable).approve(targetPool, 0);
            IERC20(stable).safeTransfer(vault, _amount);

            emit Failure(_response, block.timestamp);
        }
    } 

    function removeLiquidity(uint _amount) external onlyHandler(vault) nonReentrant() returns(bool success, uint earnedAmount) {
        bytes memory _response;

        IERC20(aToken).approve(targetPool, IERC20(aToken).balanceOf(address(this)));
        (success, _response) = targetPool.call(
            abi.encodeWithSignature("withdraw(address,uint256,address)", stable, _amount, vault)
        ); 

        if(success){
            uint _stableAmount = abi.decode(_response, (uint256));

            if(initStableAmount >= _stableAmount){
                initStableAmount -= _stableAmount;
            } else {
                earnedAmount = _stableAmount - initStableAmount;
                initStableAmount = 0;
            }

            if(IERC20(aToken).balanceOf(address(this)) == 0) active = false;  
        } else {
            emit Failure(_response, block.timestamp);
        }

        aTokenAmount = IERC20(aToken).balanceOf(address(this));
        IERC20(aToken).approve(targetPool, 0);
    } 

    function manualProvideLiquidity() external {
        (bool allowed, ) = checkUsage(false);
        require(allowed, "LiquidityManager: not allowed");
        IVault(vault).manualUseLiquidity();
    }

    function manualRemoveLiquidity() external {
        (bool allowed, ) = checkRemove(false);
        require(allowed, "LiquidityManager: not allowed");
        IVault(vault).manualUseLiquidity();
    }

    function checkUsage(bool _auto) public view returns(bool allowed, uint amount) {
        Settings memory slot = addSlot; 
        if(!usageEnabled) return(false, 0);
        if(active) return(false, 0);
        if(_auto && !autoUsageEnabled) return(false, 0);
        if(!_auto && !manualUsageEnabled) return(false, 0);
        if(slot.allowedShare == 0) return(false, 0);
        if(targetPool == address(0)) return(false, 0);
        if(aToken != IPool(targetPool).getReserveData(stable).aTokenAddress) return(false, 0);
        if(slot.allowedSupplyRate > IPool(targetPool).getReserveData(stable).currentLiquidityRate) return(false, 0);

        (uint _poolAmount, uint _availableLiquidity, uint _utilizationRate) = getVaultState();
        (bool _isActual, bool _hasTradersProfit, uint _totalPositionsDelta) = IPositionsTracker(positionsTracker).getPositionsData();

        if(_utilizationRate >= slot.utilizationRateKink) return(false, 0);
        if(slot.availableLiquidityKink >= _availableLiquidity) return(false, 0);
        if(slot.poolAmountKink >= _poolAmount) return(false, 0);
        if(totalPositionsConsider && !_isActual) return(false, 0);
        if(_isActual && _hasTradersProfit && _totalPositionsDelta >= slot.totalPositionsDeltaKink) return(false, 0);

        allowed = true;
        amount = _availableLiquidity.mulDiv(slot.allowedShare, Math.PRECISION);
        if(amount > slot.allowedAmount) amount = slot.allowedAmount;
    }
    
    function checkRemove(bool _auto) public view returns(bool allowed, uint amount) {
        Settings memory slot = removeSlot;
        amount = IERC20(aToken).balanceOf(address(this));
        if(aToken != IPool(targetPool).getReserveData(stable).aTokenAddress) return(false, 0);
        if(!active) return(false, 0);
        if(newImplEnabled) return(true, amount);
        if(!usageEnabled) return(false, 0);
        if(_auto && !autoUsageEnabled) return(false, 0);
        if(!_auto && !manualUsageEnabled) return(false, 0);
        
        (uint _poolAmount, uint _availableLiquidity, uint _utilizationRate) = getVaultState();
        (bool _isActual, bool _hasTradersProfit, uint _totalPositionsDelta) = IPositionsTracker(positionsTracker).getPositionsData();
        
        if(slot.allowedSupplyRate > IPool(targetPool).getReserveData(stable).currentLiquidityRate) return (true, amount);

        if(
            _utilizationRate >= slot.utilizationRateKink &&
            slot.availableLiquidityKink >= _availableLiquidity && 
            slot.poolAmountKink >= _poolAmount && 
            _isActual && _hasTradersProfit && _totalPositionsDelta >= slot.totalPositionsDeltaKink
        ) return (true, amount);

        if(
            _utilizationRate >= slot.utilizationRateKink ||
            slot.availableLiquidityKink >= _availableLiquidity || 
            slot.poolAmountKink >= _poolAmount || 
            (_isActual && _hasTradersProfit && _totalPositionsDelta >= slot.totalPositionsDeltaKink)
        ) return (true, amount.mulDiv(slot.allowedShare, Math.PRECISION));
    }

    function getVaultState() public view returns(uint poolAmount, uint availableLiquidity, uint utilizationRate) {
        IVault _vault = IVault(vault);
        return (_vault.poolAmount(), _vault.availableLiquidity(), _vault.utilizationRate());
    }
}
