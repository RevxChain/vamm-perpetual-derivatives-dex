// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/ILiquidityManagerData.sol";

contract LiquidityManagerData is ILiquidityManagerData {

    /// @custom:storage-location erc7201:RevxChain.storage.LiquidityManagerData.MainSettings
    struct MainSettings {
        uint _minRemoveAllowedShare;
        uint _initStableAmount;
        uint _aTokenAmount;
        uint _referralCode;
        address _aToken;
        address _targetPool;
        address _rewardsController;
        address _extraReward;
        bool _newImplEnabled;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("RevxChain.storage.LiquidityManagerData.MainSettings")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LiquidityManagerDataMainSettingsStorageLocation = 0x2478fc1ba83a9a2a872d8221313613f7fde171a2e75f99ace5508ebb13f09700;

    /// @dev keccak256(abi.encode(uint256(keccak256("RevxChain.storage.LiquidityManagerData.AddSettings")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LiquidityManagerDataAddSettingsStorageLocation = 0xb5fff7dd3c0fc736493e33786bfe2952c041197624529347b26a290500750200;

    /// @dev keccak256(abi.encode(uint256(keccak256("RevxChain.storage.LiquidityManagerData.RemoveSettings")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LiquidityManagerDataRemoveSettingsStorageLocation = 0xd685419b41d18827767d4dac21ac45a8fa604e78ccd8198412de0e0bb32aea00;

    function minRemoveAllowedShare() public view returns(uint) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._minRemoveAllowedShare;
    }

    function initStableAmount() public view returns(uint) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._initStableAmount;
    }

    function aTokenAmount() public view returns(uint) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._aTokenAmount;
    }

    function referralCode() public view returns(uint) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._referralCode;
    }

    function aToken() public view returns(address) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._aToken;
    }

    function targetPool() public view returns(address) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._targetPool;
    }

    function rewardsController() public view returns(address) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._rewardsController;
    }

    function extraReward() public view returns(address) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._extraReward;
    }

    function newImplEnabled() public view returns(bool) {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        return $._newImplEnabled;
    }

    function allowedSupplyRateA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._allowedSupplyRate;
    }

    function allowedAmountA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._allowedAmount;
    }

    function allowedShareA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._allowedShare;
    }

    function utilizationRateKinkA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._utilizationRateKink;
    }

    function availableLiquidityKinkA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._availableLiquidityKink;
    }

    function poolAmountKinkA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._poolAmountKink;
    }

    function totalPositionsDeltaKinkA() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        return $._totalPositionsDeltaKink;
    }

    function allowedSupplyRateR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._allowedSupplyRate;
    }

    function allowedAmountR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._allowedAmount;
    }

    function allowedShareR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._allowedShare;
    }

    function utilizationRateKinkR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._utilizationRateKink;
    }

    function availableLiquidityKinkR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._availableLiquidityKink;
    }

    function poolAmountKinkR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._poolAmountKink;
    }

    function totalPositionsDeltaKinkR() public view returns(uint) {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        return $._totalPositionsDeltaKink;
    }

    function getLiquidityManagerDataMainSettings() private pure returns(MainSettings storage $) {
        assembly {
            $.slot := LiquidityManagerDataMainSettingsStorageLocation
        }
    }

    function getLiquidityManagerDataAddSettings() private pure returns(AdditionalSettings storage $) {
        assembly {
            $.slot := LiquidityManagerDataAddSettingsStorageLocation
        }
    }

    function getLiquidityManagerDataRemoveSettings() private pure returns(AdditionalSettings storage $) {
        assembly {
            $.slot := LiquidityManagerDataRemoveSettingsStorageLocation
        }
    }

    function _setMinRemoveAllowedShare(uint newMinRemoveAllowedShare) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._minRemoveAllowedShare = newMinRemoveAllowedShare;
    }

    function _setInitStableAmount(uint newInitStableAmount) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._initStableAmount = newInitStableAmount;
    }

    function _setATokenAmount(uint newATokenAmount) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._aTokenAmount = newATokenAmount;
    }

    function _setReferralCode(uint newReferralCode) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._referralCode = newReferralCode;
    }

    function _setAToken(address newAToken) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._aToken = newAToken;
    }

    function _setTargetPool(address newTargetPool) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._targetPool = newTargetPool;
    }

    function _setRewardsController(address newRewardsController) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._rewardsController = newRewardsController;
    }

    function _setExtraReward(address newExtraReward) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._extraReward = newExtraReward;
    }

    function _setNewImplEnabled(bool enableNewImplEnabled) internal {
        MainSettings storage $ = getLiquidityManagerDataMainSettings();
        $._newImplEnabled = enableNewImplEnabled;
    }

    function _setAllowedSupplyRateA(uint newAllowedSupplyRate) internal { 
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._allowedSupplyRate = newAllowedSupplyRate;
    }

    function _setAllowedAmountA(uint newAllowedAmount) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._allowedAmount = newAllowedAmount;
    }

    function _setAllowedShareA(uint newAllowedShare) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._allowedShare = newAllowedShare;
    }

    function _setUtilizationRateKinkA(uint newUtilizationRateKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._utilizationRateKink = newUtilizationRateKink;
    }

    function _setAvailableLiquidityKinkA(uint newAvailableLiquidityKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._availableLiquidityKink = newAvailableLiquidityKink;
    }

    function _setPoolAmountKinkA(uint newPoolAmountKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._poolAmountKink = newPoolAmountKink;
    }

    function _setTotalPositionsDeltaKinkA(uint newTotalPositionsDeltaKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataAddSettings();
        $._totalPositionsDeltaKink = newTotalPositionsDeltaKink;
    }

    function _setAllowedSupplyRateR(uint newAllowedSupplyRate) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._allowedSupplyRate = newAllowedSupplyRate;
    }

    function _setAllowedAmountR(uint newAllowedAmount) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._allowedAmount = newAllowedAmount;
    }

    function _setAllowedShareR(uint newAllowedShare) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._allowedShare = newAllowedShare;
    }

    function _setUtilizationRateKinkR(uint newUtilizationRateKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._utilizationRateKink = newUtilizationRateKink;
    }

    function _setAvailableLiquidityKinkR(uint newAvailableLiquidityKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._availableLiquidityKink = newAvailableLiquidityKink;
    }

    function _setPoolAmountKinkR(uint newPoolAmountKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._poolAmountKink = newPoolAmountKink;
    }

    function _setTotalPositionsDeltaKinkR(uint newTotalPositionsDeltaKink) internal {
        AdditionalSettings storage $ = getLiquidityManagerDataRemoveSettings();
        $._totalPositionsDeltaKink = newTotalPositionsDeltaKink;
    }

    function _setAddSettings(
        uint __allowedSupplyRate,
        uint __allowedAmount,
        uint __allowedShare,
        uint __utilizationRateKink, 
        uint __availableLiquidityKink,
        uint __poolAmountKink,
        uint __totalPositionsDeltaKink
    ) internal {
        _setAllowedSupplyRateA(__allowedSupplyRate);
        _setAllowedAmountA(__allowedAmount); 
        _setAllowedShareA(__allowedShare); 
        _setUtilizationRateKinkA(__utilizationRateKink);  
        _setAvailableLiquidityKinkA(__availableLiquidityKink); 
        _setPoolAmountKinkA(__poolAmountKink); 
        _setTotalPositionsDeltaKinkA(__totalPositionsDeltaKink);
    }

    function _setRemoveSettings(
        uint __allowedSupplyRate,
        uint __allowedAmount,
        uint __allowedShare,
        uint __utilizationRateKink, 
        uint __availableLiquidityKink,
        uint __poolAmountKink,
        uint __totalPositionsDeltaKink
    ) internal {
        _setAllowedSupplyRateR(__allowedSupplyRate);
        _setAllowedAmountR(__allowedAmount); 
        _setAllowedShareR(__allowedShare); 
        _setUtilizationRateKinkR(__utilizationRateKink);  
        _setAvailableLiquidityKinkR(__availableLiquidityKink); 
        _setPoolAmountKinkR(__poolAmountKink); 
        _setTotalPositionsDeltaKinkR(__totalPositionsDeltaKink);
    }

    function _deleteMainSettings() internal {
        _setMinRemoveAllowedShare(0);
        _setInitStableAmount(0); 
        _setATokenAmount(0); 
        _setReferralCode(0);
        _setAToken(address(0)); 
        _setTargetPool(address(0)); 
        _setRewardsController(address(0));  
        _setExtraReward(address(0));  
        _setNewImplEnabled(false);
    }

    function _deleteAddSettings() internal {
        _setAllowedSupplyRateA(0);
        _setAllowedAmountA(0); 
        _setAllowedShareA(0); 
        _setUtilizationRateKinkA(0);  
        _setAvailableLiquidityKinkA(0); 
        _setPoolAmountKinkA(0); 
        _setTotalPositionsDeltaKinkA(0);
    }

    function _deleteRemoveSettings() internal {
        _setAllowedSupplyRateR(0);
        _setAllowedAmountR(0); 
        _setAllowedShareR(0); 
        _setUtilizationRateKinkR(0);  
        _setAvailableLiquidityKinkR(0); 
        _setPoolAmountKinkR(0); 
        _setTotalPositionsDeltaKinkR(0);
    }
}