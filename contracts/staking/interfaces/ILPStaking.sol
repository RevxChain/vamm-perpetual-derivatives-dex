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
    function rewardToken() external view returns(address);
    
    function setMinLockDuration(uint _minLockDuration) external;

    function setExtraRate(uint _extraRate) external;

    function stake(uint _amount, uint _lockDuration) external;

    function collectRewards(bool _baseReward, bool _extraReward) external;

    function unstake() external;

    function addRewards(uint _amount, uint _extraAmount) external;

    function preUpdateInitShares() external view returns(uint);

    function preUpdateTimeSharesPool() external view returns(uint);

    function preUpdateUserTimeShares(address _user) external view returns(uint);

    function calculateUserBaseReward(address _user) external view returns(uint);

    function calculateUserExtraReward(address _user) external view returns(uint);

    function calculateUserAmount(address _user) external view returns(uint);

    function calculateUserRate(address _user) external view returns(uint);
    
}