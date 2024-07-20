// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./LiquidityManagerData.sol";
import "../libraries/ImplementationSlot.sol";
import "../libraries/GovernableUpgradeable.sol";
import "../libraries/Math.sol";

import "../libraries/interfaces/ILiquidityManagerBase.sol";
import "../core/interfaces/IPositionsTracker.sol";
import "../core/interfaces/IVault.sol";

contract LiquidityManagerIMPL is 
    ImplementationSlot, 
    LiquidityManagerData, 
    ILiquidityManagerBase, 
    GovernableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using SafeERC20 for IERC20;   
    using Math for uint;

    event Success(bytes response, uint time);
    event Failure(bytes response, uint time);

    function initialize(
        address _vault,
        address _stable,
        address _positionsTracker,
        address _poolTarget,
        address _rewardsController,
        address _extraReward
    ) external initializer() {  
        require(!isInitialized(), "LiquidityManager: initialized");
        _setIsInitialized(true);

        __ReentrancyGuard_init();

        _setGov(msg.sender); 
        _setDao(msg.sender);
        _setVault(_vault);
        _setStable(_stable);
        _setPositionsTracker(_positionsTracker);
        _setStrategy("AAVEv3 Pure Supply v1.0");

        _setTargetPool(_poolTarget);
        _setAToken(IPool(_poolTarget).getReserveData(_stable).aTokenAddress);
        _setRewardsController(_rewardsController);
        _setExtraReward(_extraReward);

        _setUsageEnabled(true); 
        _setManualUsageEnabled(true);
        _setTotalPositionsConsider(true);

        _setMinRemoveAllowedShare(1000);
    }

    function setNewImplementation(address newImplementation, string calldata newStrategy, bool claimRewards) external onlyHandler(dao()) {
        require(isInitialized(), "LiquidityManager: not initialized");
        if(active()){
            _setNewImplEnabled(true);
            IVault(vault()).manualUseLiquidity();
        }
        require(!active(), "LiquidityManager: active");

        if(claimRewards){
            address[] memory _tokens = new address[](1);
            _tokens[0] = aToken();
            IRewardsController(rewardsController()).claimRewards(_tokens, type(uint).max, gov(), extraReward());
        }
        
        _deleteAddSettings();
        _deleteRemoveSettings();
        _deleteMainSettings();

        _setUsageEnabled(false);
        _setAutoUsageEnabled(false);
        _setManualUsageEnabled(false);

        _setStrategy(newStrategy);
        _setImplementation(newImplementation);
    }

    function setStrategySettings(
        AdditionalSettings calldata addSetup, 
        AdditionalSettings calldata removeSetup
    ) external onlyHandler(dao()) {
        string memory _error = "LiquidityManager: invalid settings";
        require(isInitialized(), "LiquidityManager: not initialized");
        require(!active(), "LiquidityManager: active");
        require(targetPool() != address(0), "LiquidityManager: main settings not initialized");
        require(addSetup._allowedSupplyRate > removeSetup._allowedSupplyRate, _error);
        require(removeSetup._utilizationRateKink > addSetup._utilizationRateKink, _error);
        require(addSetup._availableLiquidityKink > removeSetup._availableLiquidityKink, _error);
        require(addSetup._poolAmountKink > removeSetup._poolAmountKink, _error);
        require(removeSetup._totalPositionsDeltaKink > addSetup._totalPositionsDeltaKink, _error);
        require(Math.PRECISION >= addSetup._allowedShare, _error);
        require(Math.PRECISION >= removeSetup._allowedShare, _error);
        require(removeSetup._allowedShare >= minRemoveAllowedShare(), _error);

        _setAddSettings(
            addSetup._allowedSupplyRate,
            addSetup._allowedAmount,
            addSetup._allowedShare,
            addSetup._utilizationRateKink, 
            addSetup._availableLiquidityKink,
            addSetup._poolAmountKink,
            addSetup._totalPositionsDeltaKink
        );

        _setRemoveSettings(
            removeSetup._allowedSupplyRate,
            removeSetup._allowedAmount,
            removeSetup._allowedShare,
            removeSetup._utilizationRateKink, 
            removeSetup._availableLiquidityKink,
            removeSetup._poolAmountKink,
            removeSetup._totalPositionsDeltaKink
        );
    }

    function setUsageEnabled(bool enabled) external onlyHandler(dao()) {
        require(!active(), "LiquidityManager: active");
        _setUsageEnabled(enabled);
    }

    function setAutoUsageEnabled(bool enabled) external onlyHandler(dao()) {
        _setAutoUsageEnabled(enabled);
    }

    function setManualUsageEnabled(bool enabled) external onlyHandler(dao()) {
        _setManualUsageEnabled(enabled);
    }

    function setTotalPositionsConsider(bool consider) external onlyHandler(dao()) {
        _setTotalPositionsConsider(consider);
    }

    function provideLiquidity(uint amount) external onlyHandler(vault()) nonReentrant() returns(bool success, uint usedAmount) {
        if(amount > IERC20(stable()).balanceOf(address(this))){
            IERC20(stable()).safeTransfer(vault(), IERC20(stable()).balanceOf(address(this)));
            return (false, 0);
        }
        
        if(allowedAmountA() > amount) _setAllowedAmountA(amount);
        
        bytes memory _response;
        IERC20(stable()).approve(targetPool(), amount);
        (success, _response) = targetPool().call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", stable(), amount, address(this), referralCode()
            )
        ); 

        if(success){
            _setActive(true);
            _setInitStableAmount(amount);
            _setATokenAmount(IERC20(aToken()).balanceOf(address(this)));
            usedAmount = amount;

            emit Success(_response, block.timestamp);
        } else {
            IERC20(stable()).approve(targetPool(), 0);
            IERC20(stable()).safeTransfer(vault(), amount);

            emit Failure(_response, block.timestamp);
        }
    } 

    function removeLiquidity(uint amount) external onlyHandler(vault()) nonReentrant() returns(bool success, uint earnedAmount) {
        bytes memory _response;

        (success, _response) = targetPool().call(
            abi.encodeWithSignature("withdraw(address,uint256,address)", stable(), amount, vault())
        ); 

        if(success){
            uint _stableAmount = abi.decode(_response, (uint256));

            if(initStableAmount() >= _stableAmount){
                _setInitStableAmount(initStableAmount() - _stableAmount);
            } else {
                earnedAmount = _stableAmount - initStableAmount();
                _setInitStableAmount(0);
            }

            if(IERC20(aToken()).balanceOf(address(this)) == 0) _setActive(false);  
        } else {
            emit Failure(_response, block.timestamp);
        }

        _setATokenAmount(IERC20(aToken()).balanceOf(address(this)));
        IERC20(aToken()).approve(targetPool(), 0);
    } 

    function manualProvideLiquidity() external {
        (bool allowed, ) = checkUsage(false);
        require(allowed, "LiquidityManager: not allowed");
        IVault(vault()).manualUseLiquidity();
    }

    function manualRemoveLiquidity() external {
        (bool allowed, ) = checkRemove(false);
        require(allowed, "LiquidityManager: not allowed");
        IVault(vault()).manualUseLiquidity();
    }

    function checkUsage(bool autoUsage) public view returns(bool allowed, uint amount) {
        if(!usageEnabled()) return(false, 0);
        if(active()) return(false, 0);
        if(autoUsage && !autoUsageEnabled()) return(false, 0);
        if(!autoUsage && !manualUsageEnabled()) return(false, 0);
        if(allowedShareA() == 0) return(false, 0);
        if(targetPool() == address(0)) return(false, 0);
        if(aToken() != IPool(targetPool()).getReserveData(stable()).aTokenAddress) return(false, 0);
        if(allowedSupplyRateA() > IPool(targetPool()).getReserveData(stable()).currentLiquidityRate) return(false, 0);

        (uint _poolAmount, uint _availableLiquidity, uint _utilizationRate) = getVaultState();
        (bool _isActual, bool _hasTradersProfit, uint _totalPositionsDelta) = IPositionsTracker(positionsTracker()).getPositionsData();

        if(_utilizationRate >= utilizationRateKinkA()) return(false, 0);
        if(availableLiquidityKinkA() >= _availableLiquidity) return(false, 0);
        if(poolAmountKinkA() >= _poolAmount) return(false, 0);
        if(totalPositionsConsider() && !_isActual) return(false, 0);
        if(_isActual && _hasTradersProfit && _totalPositionsDelta >= totalPositionsDeltaKinkA()) return(false, 0);

        allowed = true;
        amount = _availableLiquidity.mulDiv(allowedShareA(), Math.PRECISION);
        if(amount > allowedAmountA()) amount = allowedAmountA();
    }
    
    function checkRemove(bool autoUsage) public view returns(bool allowed, uint amount) {
        amount = IERC20(aToken()).balanceOf(address(this));
        if(aToken() != IPool(targetPool()).getReserveData(stable()).aTokenAddress) return(false, 0);
        if(!active()) return(false, 0);
        if(newImplEnabled()) return(true, amount);
        if(!usageEnabled()) return(false, 0);
        if(autoUsage && !autoUsageEnabled()) return(false, 0);
        if(!autoUsage && !manualUsageEnabled()) return(false, 0);
        
        (uint _poolAmount, uint _availableLiquidity, uint _utilizationRate) = getVaultState();
        (bool _isActual, bool _hasTradersProfit, uint _totalPositionsDelta) = IPositionsTracker(positionsTracker()).getPositionsData();
        
        if(allowedSupplyRateR() > IPool(targetPool()).getReserveData(stable()).currentLiquidityRate) return (true, amount);

        if(
            _utilizationRate >= utilizationRateKinkR() &&
            availableLiquidityKinkR() >= _availableLiquidity && 
            poolAmountKinkR() >= _poolAmount && 
            _isActual && _hasTradersProfit && _totalPositionsDelta >= totalPositionsDeltaKinkR()
        ) return (true, amount);

        if(
            _utilizationRate >= utilizationRateKinkR() ||
            availableLiquidityKinkR() >= _availableLiquidity || 
            poolAmountKinkR() >= _poolAmount || 
            (_isActual && _hasTradersProfit && _totalPositionsDelta >= totalPositionsDeltaKinkR())
        ) return (true, amount.mulDiv(allowedShareR(), Math.PRECISION));
    }

    function getVaultState() public view returns(uint poolAmount, uint availableLiquidity, uint utilizationRate) {
        IVault _vault = IVault(vault());
        return (_vault.poolAmount(), _vault.availableLiquidity(), _vault.utilizationRate());
    }
}