// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILPStaking {

    function pool() external view returns(uint);
    function sharesPool() external view returns(uint);
    function minLockDuration() external view returns(uint);
    function extraRate() external view returns(uint);
    function timeSharesPool() external view returns(uint);
    function lastUpdated() external view returns(uint);
    function membersCount() external view returns(uint);
    function initShares() external view returns(uint);
    function extraRewardPool() external view returns(uint);
    
    function lpManager() external view returns(address);
    function stakedToken() external view returns(address); 
    function rewardToken() external view returns(address);
    
    function setMinLockDuration(uint newMinLockDuration) external;

    function setExtraRate(uint newExtraRate) external;

    function stakeLP(uint amount, uint lockDuration) external;

    function collectRewards(bool baseReward, bool extraReward) external;

    function unstakeLP() external;

    function addRewards(uint amount, uint extraAmount) external;

    function preUpdateInitShares() external view returns(uint);

    function preUpdateTimeSharesPool() external view returns(uint);

    function preUpdateUserTimeShares(address user) external view returns(uint);

    function calculateUserBaseReward(address user) external view returns(uint);

    function calculateUserExtraReward(address user) external view returns(uint);

    function calculateUserAmount(address user) external view returns(uint);

    function calculateUserRate(address user) external view returns(uint);

    function getUserStakeInfo(address user) external view returns(
        uint underlyingBalance,
        uint totalBalance,
        uint baseReward,
        uint extraReward,
        uint amountShares,
        uint timeShares,
        uint stakeStart,
        uint lockDuration,
        uint lastUpdatedTimestamp
    );
    
}