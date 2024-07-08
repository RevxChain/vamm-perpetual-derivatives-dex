// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BorrowingModule.sol";

import "./interfaces/IVAMM.sol";
import "../oracle/interfaces/IPriceFeed.sol";

contract FundingModule is BorrowingModule {
    using Math for uint;

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

    function setFundingPriceMultiplier(uint newFundingPriceMultiplier) external onlyHandler(dao) {
        validate(MAX_FUNDING_PRICE_MULTIPLIER >= newFundingPriceMultiplier , 31);
        validate(newFundingPriceMultiplier >= Math.INIT_LOCK_AMOUNT, 32);
        fundingPriceMultiplier = newFundingPriceMultiplier;
    }

    function updateTotalFunding(address indexToken) public returns(uint, uint) {
        Funding storage funding = fundings[indexToken];
        if(block.timestamp > funding.lastFundingUpdateTime){
            (funding.totalLongFunding, funding.totalShortFunding) = preUpdateTotalFunding(indexToken);
            funding.lastFundingUpdateTime = block.timestamp;
        }

        return (funding.totalLongFunding, funding.totalShortFunding);
    }

    function preUpdateTotalFunding(address indexToken) public view returns(uint, uint) {
        Funding memory funding = fundings[indexToken];
        uint _updateTime = funding.lastFundingUpdateTime;
        if(block.timestamp > _updateTime){
            uint _vammPrice = IVAMM(VAMM).getPrice(indexToken);
            uint _feedPrice = IPriceFeed(priceFeed).getPrice(indexToken);
            uint _fundingFeeRate = (getPriceDelta(_vammPrice, _feedPrice).mulDiv(Math.ACCURACY, _vammPrice)).mulDiv(fundingPriceMultiplier, Math.PRECISION); 
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
        address user, 
        address indexToken, 
        bool long
    ) public view returns(uint delta, bool hasProfit, uint fundingFeeDebt, uint fundingFeeGain) {
        bytes32 _key = calculatePositionKey(user, indexToken, long);
        Funding memory funding = fundings[indexToken];
        Position memory position = positions[_key];
        (uint _totalLongFunding, uint _totalShortFunding) = preUpdateTotalFunding(indexToken);

        if(long){
            fundingFeeDebt = position.entryFunding.mulDiv(_totalLongFunding, funding.fundingLongSharePool);
            fundingFeeGain = position.entryFunding.mulDiv(funding.fundingLongFeeAmount, funding.fundingLongSharePool);
        } else {
            fundingFeeDebt = position.entryFunding.mulDiv(_totalShortFunding, funding.fundingShortSharePool); 
            fundingFeeGain = position.entryFunding.mulDiv(funding.fundingShortFeeAmount, funding.fundingShortSharePool);
        }

        fundingFeeDebt = fundingFeeDebt > position.size ? fundingFeeDebt - position.size : 0;
        if(fundingFeeGain > fundingFeeDebt){
            delta = fundingFeeGain - fundingFeeDebt;
            hasProfit = true;
        } else {
            delta = fundingFeeDebt - fundingFeeGain;
        }
    }

    function calculateUserFundingFeeDebt(bytes32 key, address indexToken, bool long) internal view returns(uint) {
        Funding memory funding = fundings[indexToken];
        Position memory position = positions[key];
        return long ?
        position.entryFunding.mulDiv(funding.totalLongFunding, funding.fundingLongSharePool) : 
        position.entryFunding.mulDiv(funding.totalShortFunding, funding.fundingShortSharePool);
    }

    function setFundingTokenConfig(address indexToken) internal {     
        fundings[indexToken] = Funding({
            totalLongFunding: Math.INIT_LOCK_AMOUNT,
            totalShortFunding: Math.INIT_LOCK_AMOUNT,
            fundingLongSharePool: Math.INIT_LOCK_AMOUNT,
            fundingShortSharePool: Math.INIT_LOCK_AMOUNT,
            fundingLongFeeAmount: Math.INIT_LOCK_AMOUNT,
            fundingShortFeeAmount: Math.INIT_LOCK_AMOUNT,
            lastFundingUpdateTime: block.timestamp
        });
    }

    function deleteFundingTokenConfig(address indexToken) internal {     
        delete fundings[indexToken];
    }

    function getEntryFunding(bytes32 key, address indexToken, uint sizeDelta, bool long) internal { 
        Funding storage funding = fundings[indexToken];
        Position storage position = positions[key];
        uint _userShares;
        if(long){
            _userShares = sizeDelta.mulDiv(funding.fundingLongSharePool, funding.totalLongFunding);
            position.entryFunding += _userShares;
            funding.fundingLongSharePool += _userShares;
            funding.totalLongFunding += sizeDelta;
        } else {
            _userShares = sizeDelta.mulDiv(funding.fundingShortSharePool, funding.totalShortFunding);
            position.entryFunding += _userShares;
            funding.fundingShortSharePool += _userShares;
            funding.totalShortFunding += sizeDelta;
        }
    }

    function collectFundingFee(
        address user, 
        address indexToken, 
        bool long
    ) internal returns(uint delta, bool hasProfit) {
        Funding storage funding = fundings[indexToken];
        (uint _fundingFeeDebt, uint _fundingFeeGain) = (0, 0);
        (delta, hasProfit, _fundingFeeDebt, _fundingFeeGain) = preCalculateUserFundingFee(user, indexToken, long);
        
        if(long){
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
        bytes32 key, 
        address indexToken, 
        uint sizeDelta,
        bool long
    ) internal {
        Funding storage funding = fundings[indexToken];
        Position storage position = positions[key];
        uint _userFundingFeeDebt = 
        calculateUserFundingFeeDebt(key, indexToken, long) > sizeDelta ? 
        calculateUserFundingFeeDebt(key, indexToken, long) - sizeDelta : 0;
        uint _sharePoolDecrease;
        if(_userFundingFeeDebt > 0){
            if(long){
                _sharePoolDecrease = _userFundingFeeDebt.mulDiv(funding.fundingLongSharePool, funding.totalLongFunding);
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
                funding.fundingLongSharePool = Math.INIT_LOCK_AMOUNT : funding.fundingLongSharePool -= _sharePoolDecrease;

                _userFundingFeeDebt >= funding.totalLongFunding ? 
                funding.totalLongFunding = Math.INIT_LOCK_AMOUNT : funding.totalLongFunding -= _userFundingFeeDebt;
            } else {
                _sharePoolDecrease = _userFundingFeeDebt.mulDiv(funding.fundingShortSharePool, funding.totalShortFunding);
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
                funding.fundingShortSharePool = Math.INIT_LOCK_AMOUNT : funding.fundingShortSharePool -= _sharePoolDecrease;
                
                _userFundingFeeDebt >= funding.totalShortFunding ? 
                funding.totalShortFunding = Math.INIT_LOCK_AMOUNT : funding.totalShortFunding -= _userFundingFeeDebt;
            }
        } 
    }
}