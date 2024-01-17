// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../tokens/interfaces/IStakedSupplyToken.sol";
import "../libraries/Governable.sol";
import "../libraries/Math.sol";

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

    function setMinLockDuration(uint _minLockDuration) external onlyHandler(dao) {
        require(_minLockDuration >= MIN_LOCK_DURATION, "LPStaking: minLockDuration underflow");
        require(Math.ONE_YEAR >= _minLockDuration, "LPStaking: minLockDuration overflow");
        minLockDuration = _minLockDuration;
    }

    function setExtraRate(uint _extraRate) external onlyHandler(dao) {
        extraRate = _extraRate;
    }

    function stakeLP(uint _amount, uint _lockDuration) external nonReentrant() {
        address _user = msg.sender;
        require(IERC20(stakedToken).balanceOf(_user) == 0, "LPStaking: stake already");
        require(_lockDuration >= minLockDuration, "LPStaking: lockDuration underflow");
        require(Math.ONE_YEAR >= _lockDuration, "LPStaking: lockDuration overflow");
        require(IERC20(LPManager).balanceOf(_user) >= _amount, "LPStaking: invalid balance");
        require(_amount > 0, "LPStaking: invalid amount"); 
        if(timeSharesPool == 0) lastUpdated = block.timestamp;

        uint _initShares = updateTimeSharesPool() + _lockDuration;
        timeSharesPool += _initShares;
        membersCount += 1;

        uint _userShare; 
        if(sharesPool > 0){
            _userShare = _amount.mulDiv(sharesPool, pool);
        } else {
            _userShare = _amount;
            initStake(); 
        }

        pool += _amount;
        sharesPool += _userShare;

        IStakedSupplyToken(stakedToken).mint(_user, _amount);

        stakers[_user] = Stake({
            amountShares: _userShare,
            stakeStart: block.timestamp,
            lockDuration: _lockDuration,
            timeShares: _initShares,
            lastTimestamp: block.timestamp,
            extraRewardClaimed: 0
        });

        IERC20(LPManager).safeTransferFrom(_user, address(this), _amount);
    }

    function collectRewards(bool _baseReward, bool _extraReward) external nonReentrant() {
        address _user = msg.sender;
        Stake storage stake = stakers[_user];
        require(_baseReward || _extraReward, "LPStaking: no rewards");
        require(stake.lastTimestamp > 0, "LPStaking: not a staker");
        updateTimeSharesPool();
        updateUserTimeShares(_user);

        if(_baseReward){
            uint _baseRewardAmount = calculateUserBaseReward(_user);
            require(IERC20(LPManager).balanceOf(address(this)) >= _baseRewardAmount, "LPStaking: invalid balance");
            uint _sharePoolDecrease = _baseRewardAmount.mulDiv(sharesPool, pool);
            stake.amountShares -= _sharePoolDecrease; 
            sharesPool -= _sharePoolDecrease;
            pool -= _baseRewardAmount;
            IERC20(LPManager).safeTransfer(_user, _baseRewardAmount);
        }

        if(_extraReward) collectExtraRewards(_user);
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

    function addRewards(uint _amount, uint _extraAmount) external nonReentrant() {
        address _user = msg.sender;
        require(_amount > 0 || _extraAmount > 0, "LPStaking: invalid amount"); 
        require(IERC20(LPManager).balanceOf(_user) >= _amount, "LPStaking: invalid balance");
        require(IERC20(rewardToken).balanceOf(_user) >= _extraAmount, "LPStaking: invalid balance");
        pool += _amount;
        extraRewardPool += _extraAmount;
        if(_amount > 0) IERC20(LPManager).safeTransferFrom(_user, address(this), _amount);
        if(_extraAmount > 0) IERC20(rewardToken).safeTransferFrom(_user, address(this), _extraAmount);
    }

    function getUserStakeInfo(address _user) external view returns(
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
        Stake memory stake = stakers[_user];
        return (
            IERC20(stakedToken).balanceOf(_user),
            calculateUserAmount(_user),
            calculateUserBaseReward(_user),
            calculateUserExtraReward(_user),
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

    function preUpdateUserTimeShares(address _user) public view returns(uint) {
        Stake memory stake = stakers[_user];
        return stake.lastTimestamp == 0 ? 0 : stake.timeShares + (block.timestamp - stake.lastTimestamp);
    }

    function calculateUserBaseReward(address _user) public view returns(uint) {
        return calculateUserAmount(_user) - IERC20(stakedToken).balanceOf(_user);
    }

    function calculateUserExtraReward(address _user) public view returns(uint) {
        Stake memory stake = stakers[_user];
        return calculateRewardIncrease(
            IERC20(stakedToken).balanceOf(_user), 
            calculateUserRate(_user), 
            stake.lastTimestamp
        ) - stake.extraRewardClaimed;
    }

    function calculateUserAmount(address _user) public view returns(uint) {
        return stakers[_user].amountShares.mulDiv(pool, sharesPool);
    }

    function calculateUserRate(address _user) public view returns(uint) {
        return preUpdateUserTimeShares(_user).mulDiv(extraRate, preUpdateTimeSharesPool());
    } 

    function calculateRewardIncrease(uint _staked, uint _rate, uint _lastUpdate) internal view returns(uint) {
        return (_staked * _rate * ((block.timestamp - _lastUpdate).mulDiv(Math.ACCURACY, Math.ONE_YEAR))) / Math.DOUBLE_ACC;
    }

    function updateUserTimeShares(address _user) internal returns(uint) {
        Stake storage stake = stakers[_user];
        stake.timeShares = preUpdateUserTimeShares(_user);
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

    function collectExtraRewards(address _user) internal {
        Stake storage stake = stakers[_user];
        uint _extraRewardAmount = calculateUserExtraReward(_user);
        require(IERC20(rewardToken).balanceOf(address(this)) >= _extraRewardAmount, "LPStaking: invalid balance");
        extraRewardPool -= _extraRewardAmount;
        stake.extraRewardClaimed += _extraRewardAmount;
        IERC20(rewardToken).safeTransfer(_user, _extraRewardAmount);
    }
}