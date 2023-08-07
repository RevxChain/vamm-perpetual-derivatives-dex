// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BorrowingModule.sol";
import "./interfaces/IVAMM.sol";
import "../oracle/interfaces/IPriceFeed.sol";

contract FundingModule is BorrowingModule {

    uint public constant MAX_FUNDING_PRICE_MULTIPLIER = 30000; 

    uint public fundingPriceMultiplier;

    mapping(address => Funding) public fundings;
    
    struct Funding {
        uint totalLongFunding; 
        uint totalShortFunding;
        uint fundingLongSharePool; 
        uint fundingShortSharePool;
        uint fundingLongFeeAmount;
        uint fundingShortFeeAmount; 
        uint lastFundingUpdateTime; 
    }

    function setFundingPriceMultiplier(uint _fundingPriceMultiplier) external onlyHandler(dao) {
        validate(MAX_FUNDING_PRICE_MULTIPLIER >= _fundingPriceMultiplier , 31);
        validate(_fundingPriceMultiplier >= INIT_LOCK_AMOUNT, 32);
        fundingPriceMultiplier = _fundingPriceMultiplier;
    }

    function updateTotalFunding(address _indexToken) public returns(uint, uint) {
        Funding storage funding = fundings[_indexToken];
        if(block.timestamp - funding.lastFundingUpdateTime > 0){
            (funding.totalLongFunding, funding.totalShortFunding) = preUpdateTotalFunding(_indexToken);
            funding.lastFundingUpdateTime = block.timestamp;
        }

        return (funding.totalLongFunding, funding.totalShortFunding);
    }

    function preUpdateTotalFunding(address _indexToken) public view returns(uint, uint) {
        Funding memory funding = fundings[_indexToken];
        uint _updateTime = funding.lastFundingUpdateTime;
        if(block.timestamp - _updateTime > 0){
            uint _vammPrice = IVAMM(VAMM).getPrice(_indexToken);
            uint _feedPrice = IPriceFeed(priceFeed).getPrice(_indexToken);
            uint _priceDelta = _vammPrice > _feedPrice ? _vammPrice - _feedPrice : _feedPrice - _vammPrice;
            uint _fundingFeeRate = (_priceDelta * ACCURACY / _vammPrice) * fundingPriceMultiplier / PRECISION; 
            uint _totalFundingIncrease;

            if(_vammPrice > _feedPrice){
                _totalFundingIncrease = calculatePoolIncrease(funding.totalLongFunding, _fundingFeeRate, _updateTime);
                return (funding.totalLongFunding + _totalFundingIncrease, funding.totalShortFunding);
            }

            if(_vammPrice < _feedPrice){
                _totalFundingIncrease = calculatePoolIncrease(funding.totalShortFunding, _fundingFeeRate, _updateTime);
                return (funding.totalLongFunding, funding.totalShortFunding + _totalFundingIncrease);
            }
        } 
        
        return (funding.totalLongFunding, funding.totalShortFunding);
    }

    function preCalculateUserFundingFee(
        address _user, 
        address _indexToken, 
        bool _long
    ) public view returns(uint delta, bool hasProfit, uint fundingFeeDebt, uint fundingFeeGain) {
        bytes32 _key = calculatePositionKey(_user, _indexToken, _long);
        Funding memory funding = fundings[_indexToken];
        Position memory position = positions[_key];
        (uint _totalLongFunding, uint _totalShortFunding) = preUpdateTotalFunding(_indexToken);

        if(_long){
            fundingFeeDebt = position.entryFunding * _totalLongFunding / funding.fundingLongSharePool; 
            fundingFeeGain = position.entryFunding * funding.fundingLongFeeAmount / funding.fundingLongSharePool;
        } else {
            fundingFeeDebt = position.entryFunding * _totalShortFunding / funding.fundingShortSharePool; 
            fundingFeeGain = position.entryFunding * funding.fundingShortFeeAmount / funding.fundingShortSharePool; 
        }

        fundingFeeDebt = fundingFeeDebt > position.size ? fundingFeeDebt - position.size : 0;
        if(fundingFeeGain > fundingFeeDebt){
            delta = fundingFeeGain - fundingFeeDebt;
            hasProfit = true;
        } else {
            delta = fundingFeeDebt - fundingFeeGain;
        }
    }

    function calculateUserFundingFeeDebt(bytes32 _key, address _indexToken, bool _long) internal view returns(uint) {
        Funding memory funding = fundings[_indexToken];
        Position memory position = positions[_key];
        return _long ?
        position.entryFunding * funding.totalLongFunding / funding.fundingLongSharePool :
        position.entryFunding * funding.totalShortFunding / funding.fundingShortSharePool;
    }

    function setFundingTokenConfig(address _indexToken) internal {     
        Funding storage funding = fundings[_indexToken];
        funding.totalLongFunding = INIT_LOCK_AMOUNT; 
        funding.totalShortFunding = INIT_LOCK_AMOUNT;  
        funding.fundingLongSharePool = INIT_LOCK_AMOUNT;
        funding.fundingShortSharePool = INIT_LOCK_AMOUNT;
        funding.fundingLongFeeAmount = INIT_LOCK_AMOUNT;
        funding.fundingShortFeeAmount = INIT_LOCK_AMOUNT;
        funding.lastFundingUpdateTime = block.timestamp;
    }

    function deleteFundingTokenConfig(address _indexToken) internal {     
        delete fundings[_indexToken];
    }

    function getEntryFunding(bytes32 _key, address _indexToken, uint _sizeDelta, bool _long) internal { 
        Funding storage funding = fundings[_indexToken];
        Position storage position = positions[_key];
        uint _userShares;
        if(_long){
            _userShares = _sizeDelta * funding.fundingLongSharePool / funding.totalLongFunding;
            position.entryFunding += _userShares;
            funding.fundingLongSharePool += _userShares;
            funding.totalLongFunding += _sizeDelta;
        } else {
            _userShares = _sizeDelta * funding.fundingShortSharePool / funding.totalShortFunding;
            position.entryFunding += _userShares;
            funding.fundingShortSharePool += _userShares;
            funding.totalShortFunding += _sizeDelta;
        }
    }

    function collectFundingFee(
        address _user, 
        address _indexToken, 
        bool _long
    ) internal returns(uint delta, bool hasProfit) {
        Funding storage funding = fundings[_indexToken];
        uint _fundingFeeDebt;
        uint _fundingFeeGain;
        (delta, hasProfit, _fundingFeeDebt, _fundingFeeGain) = preCalculateUserFundingFee(_user, _indexToken, _long);
        if(_long){
            funding.totalLongFunding -= _fundingFeeDebt;
            funding.fundingLongFeeAmount -= _fundingFeeGain;
            if(!hasProfit) funding.fundingShortFeeAmount += delta;
        } else {
            funding.totalShortFunding -= _fundingFeeDebt;
            funding.fundingShortFeeAmount -= _fundingFeeGain; 
            if(!hasProfit) funding.fundingLongFeeAmount += delta;
        }
    }
    
    function fundingFeeRedeem(
        bytes32 _key, 
        address _indexToken, 
        uint _sizeDelta,
        bool _long
    ) internal {
        Funding storage funding = fundings[_indexToken];
        Position storage position = positions[_key];
        uint _userFundingFeeDebt = 
        calculateUserFundingFeeDebt(_key, _indexToken, _long) > _sizeDelta ? 
        calculateUserFundingFeeDebt(_key, _indexToken, _long) - _sizeDelta : 0;
        uint _sharePoolDecrease;
        if(_userFundingFeeDebt > 0){
            if(_long){
                _sharePoolDecrease = _userFundingFeeDebt * funding.fundingLongSharePool / funding.totalLongFunding;
                if(shouldValidatePoolShares) validatePoolShares(
                    funding.totalLongFunding, 
                    _userFundingFeeDebt, 
                    funding.fundingLongSharePool, 
                    _sharePoolDecrease, 
                    position.entryFunding
                );
                _sharePoolDecrease >= position.entryFunding ? 
                position.entryFunding = 0 : position.entryFunding -= _sharePoolDecrease; 
                _sharePoolDecrease >= funding.fundingLongSharePool ? 
                funding.fundingLongSharePool = INIT_LOCK_AMOUNT : funding.fundingLongSharePool -= _sharePoolDecrease;
                _userFundingFeeDebt >= funding.totalLongFunding ? 
                funding.totalLongFunding = INIT_LOCK_AMOUNT : funding.totalLongFunding -= _userFundingFeeDebt;
            } else {
                _sharePoolDecrease = _userFundingFeeDebt * funding.fundingShortSharePool / funding.totalShortFunding;
                if(shouldValidatePoolShares) validatePoolShares(
                    funding.totalShortFunding, 
                    _userFundingFeeDebt, 
                    funding.fundingShortSharePool, 
                    _sharePoolDecrease, 
                    position.entryFunding
                );
                _sharePoolDecrease >= position.entryFunding ? 
                position.entryFunding = 0 : position.entryFunding -= _sharePoolDecrease; 
                _sharePoolDecrease >= funding.fundingShortSharePool ? 
                funding.fundingShortSharePool = INIT_LOCK_AMOUNT : funding.fundingShortSharePool -= _sharePoolDecrease;
                _userFundingFeeDebt >= funding.totalShortFunding ? 
                funding.totalShortFunding = INIT_LOCK_AMOUNT : funding.totalShortFunding -= _userFundingFeeDebt;
            }
        } 
    }
}