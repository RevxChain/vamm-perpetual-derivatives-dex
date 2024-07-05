// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/Governable.sol";
import "../libraries/Math.sol";

import "../tokens/interfaces/IStakedSupplyToken.sol";

contract LPStaking is Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;    
    using Math for uint;

    uint public constant MIN_LOCK_DURATION = 1 days;
 
    uint public pool; 
    uint public sharesPool; 
    uint public minLockDuration;
    uint public extraRate;
    uint public timeSharesPool;
    uint public lastUpdated;
    uint public membersCount;
    uint public initShares;
    uint public extraRewardPool;
    
    address public LPManager;   
    address public stakedToken;
    address public rewardToken;

    bool public isInitialized;

    mapping(address => Stake) public stakers;

    struct Stake {
        uint amountShares;
        uint stakeStart;
        uint lockDuration;
        uint timeShares;
        uint lastTimestamp;
        uint extraRewardClaimed;
    }

    function initialize(
        address _LPManager, 
        address _stakedToken, 
        address _rewardToken
    ) external onlyHandler(gov) {  
        require(!isInitialized, "LPStaking: initialized");
        isInitialized = true;

        LPManager = _LPManager;
        stakedToken = _stakedToken;
        rewardToken = _rewardToken;

        minLockDuration = 7 days;
        extraRate = Math.ACCURACY;
        initShares = 10 * Math.ONE_YEAR;
    }

    function setMinLockDuration(uint newMinLockDuration) external onlyHandler(dao) {
        require(newMinLockDuration >= MIN_LOCK_DURATION, "LPStaking: minLockDuration underflow");
        require(Math.ONE_YEAR >= newMinLockDuration, "LPStaking: minLockDuration overflow");
        minLockDuration = newMinLockDuration;
    }

    function setExtraRate(uint newExtraRate) external onlyHandler(dao) {
        extraRate = newExtraRate;
    }

    function stakeLP(uint amount, uint lockDuration) external nonReentrant() {
        address _user = msg.sender;
        require(IERC20(stakedToken).balanceOf(_user) == 0, "LPStaking: stake already");
        require(lockDuration >= minLockDuration, "LPStaking: lockDuration underflow");
        require(Math.ONE_YEAR >= lockDuration, "LPStaking: lockDuration overflow");
        require(IERC20(LPManager).balanceOf(_user) >= amount, "LPStaking: invalid balance");
        require(amount > 0, "LPStaking: invalid amount"); 
        if(timeSharesPool == 0) lastUpdated = block.timestamp;

        uint _initShares = updateTimeSharesPool() + lockDuration;
        timeSharesPool += _initShares;
        membersCount += 1;

        uint _userShare; 
        if(sharesPool > 0){
            _userShare = amount.mulDiv(sharesPool, pool);
        } else {
            _userShare = amount;
            initStake(); 
        }

        pool += amount;
        sharesPool += _userShare;

        IStakedSupplyToken(stakedToken).mint(_user, amount);

        stakers[_user] = Stake({
            amountShares: _userShare,
            stakeStart: block.timestamp,
            lockDuration: lockDuration,
            timeShares: _initShares,
            lastTimestamp: block.timestamp,
            extraRewardClaimed: 0
        });

        IERC20(LPManager).safeTransferFrom(_user, address(this), amount);
    }

    function collectRewards(bool baseReward, bool extraReward) external nonReentrant() {
        address _user = msg.sender;
        Stake storage stake = stakers[_user];
        require(baseReward || extraReward, "LPStaking: no rewards");
        require(stake.lastTimestamp > 0, "LPStaking: not a staker");
        updateTimeSharesPool();
        updateUserTimeShares(_user);

        if(baseReward){
            uint _baseRewardAmount = calculateUserBaseReward(_user);
            require(IERC20(LPManager).balanceOf(address(this)) >= _baseRewardAmount, "LPStaking: invalid balance");
            uint _sharePoolDecrease = _baseRewardAmount.mulDiv(sharesPool, pool);
            stake.amountShares -= _sharePoolDecrease; 
            sharesPool -= _sharePoolDecrease;
            pool -= _baseRewardAmount;
            IERC20(LPManager).safeTransfer(_user, _baseRewardAmount);
        }

        if(extraReward) collectExtraRewards(_user);
    }

    function unstakeLP() external nonReentrant() {
        address _user = msg.sender;
        Stake storage stake = stakers[_user];
        require(stake.lastTimestamp > 0, "LPStaking: not a staker");
        require(block.timestamp >= stake.stakeStart + stake.lockDuration, "LPStaking: liquidity locked");
        
        uint _amount = calculateUserAmount(_user);
        uint _underlyingAmount = IERC20(stakedToken).balanceOf(_user);
        require(IERC20(LPManager).balanceOf(address(this)) >= _amount, "LPStaking: invalid balance");

        updateTimeSharesPool();
        updateUserTimeShares(_user);
        collectExtraRewards(_user);

        timeSharesPool -= stake.timeShares;
        membersCount -= 1;
        pool -= _amount;
        sharesPool -= stake.amountShares;

        delete stakers[_user];

        IStakedSupplyToken(stakedToken).burnFrom(_user, _underlyingAmount);
        IERC20(LPManager).safeTransfer(_user, _amount);
    }

    function addRewards(uint amount, uint extraAmount) external nonReentrant() {
        address _user = msg.sender;
        require(amount > 0 || extraAmount > 0, "LPStaking: invalid amount"); 
        require(IERC20(LPManager).balanceOf(_user) >= amount, "LPStaking: invalid balance");
        require(IERC20(rewardToken).balanceOf(_user) >= extraAmount, "LPStaking: invalid balance");
        pool += amount;
        extraRewardPool += extraAmount;
        if(amount > 0) IERC20(LPManager).safeTransferFrom(_user, address(this), amount);
        if(extraAmount > 0) IERC20(rewardToken).safeTransferFrom(_user, address(this), extraAmount);
    }

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
    ) {
        Stake memory stake = stakers[user];
        return (
            IERC20(stakedToken).balanceOf(user),
            calculateUserAmount(user),
            calculateUserBaseReward(user),
            calculateUserExtraReward(user),
            stake.amountShares,
            stake.lastTimestamp == 0 ? 0 : stake.timeShares + (block.timestamp - stake.lastTimestamp),
            stake.stakeStart,
            stake.lockDuration,
            stake.lastTimestamp
        );
    }

    function preUpdateInitShares() public view returns(uint) {
        return initShares - (block.timestamp - lastUpdated);
    }

    function preUpdateTimeSharesPool() public view returns(uint) {
        return timeSharesPool + membersCount * (block.timestamp - lastUpdated);
    }

    function preUpdateUserTimeShares(address user) public view returns(uint) {
        Stake memory stake = stakers[user];
        return stake.lastTimestamp == 0 ? 0 : stake.timeShares + (block.timestamp - stake.lastTimestamp);
    }

    function calculateUserBaseReward(address user) public view returns(uint) {
        return calculateUserAmount(user) - IERC20(stakedToken).balanceOf(user);
    }

    function calculateUserExtraReward(address user) public view returns(uint) {
        Stake memory stake = stakers[user];
        return calculateRewardIncrease(
            IERC20(stakedToken).balanceOf(user), 
            calculateUserRate(user), 
            stake.lastTimestamp
        ) - stake.extraRewardClaimed;
    }

    function calculateUserAmount(address user) public view returns(uint) {
        return stakers[user].amountShares.mulDiv(pool, sharesPool);
    }

    function calculateUserRate(address user) public view returns(uint) {
        return preUpdateUserTimeShares(user).mulDiv(extraRate, preUpdateTimeSharesPool());
    } 

    function calculateRewardIncrease(uint _staked, uint _rate, uint _lastUpdate) internal view returns(uint) {
        return (_staked * _rate * ((block.timestamp - _lastUpdate).mulDiv(Math.ACCURACY, Math.ONE_YEAR))) / Math.DOUBLE_ACC;
    }

    function updateUserTimeShares(address user) internal returns(uint) {
        Stake storage stake = stakers[user];
        stake.timeShares = preUpdateUserTimeShares(user);
        stake.lastTimestamp = block.timestamp;

        return stake.timeShares;
    }

    function updateTimeSharesPool() internal returns(uint) {
        timeSharesPool = preUpdateTimeSharesPool();
        initShares = preUpdateInitShares();
        lastUpdated = block.timestamp;

        return initShares;
    }

    function initStake() internal {
        IStakedSupplyToken(stakedToken).mint(address(this), Math.INIT_LOCK_AMOUNT);
        sharesPool = Math.INIT_LOCK_AMOUNT;
        stakers[address(this)] = Stake({
            amountShares: Math.INIT_LOCK_AMOUNT,
            stakeStart: Math.DOUBLE_ACC,
            lockDuration: Math.DOUBLE_ACC,
            timeShares: Math.INIT_LOCK_AMOUNT,
            lastTimestamp: Math.DOUBLE_ACC,
            extraRewardClaimed: 0
        });
    }

    function collectExtraRewards(address user) internal {
        Stake storage stake = stakers[user];
        uint _extraRewardAmount = calculateUserExtraReward(user);
        require(IERC20(rewardToken).balanceOf(address(this)) >= _extraRewardAmount, "LPStaking: invalid balance");
        extraRewardPool -= _extraRewardAmount;
        stake.extraRewardClaimed += _extraRewardAmount;
        IERC20(rewardToken).safeTransfer(user, _extraRewardAmount);
    }
}