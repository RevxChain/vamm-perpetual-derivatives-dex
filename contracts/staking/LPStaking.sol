// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
    
    address public lpManager;   
    address public rewardToken;

    bool public isInitialized;

    mapping(address => Stake) public stakers;

    struct Stake {
        uint staked;
        uint amountShares;
        uint stakeStart;
        uint lockDuration;
        uint timeShares;
        uint lastTimestamp;
        uint extraRewardClaimed;
    }

    function initialize(
        address _lpManager,
        address _rewardToken
    ) external onlyHandler(gov) {  
        require(!isInitialized, "LPStaking: initialized");
        isInitialized = true;

        lpManager = _lpManager;
        rewardToken = _rewardToken;

        minLockDuration = 7 days;
        extraRate = Math.ACCURACY;
        initShares = Math.PRECISION;
    }

    function setMinLockDuration(uint _minLockDuration) external onlyHandler(dao) {
        require(_minLockDuration >= MIN_LOCK_DURATION, "LPStaking: ");
        require(Math.ONE_YEAR >= _minLockDuration, "LPStaking: ");
        minLockDuration = _minLockDuration;
    }

    function setExtraRate(uint _extraRate) external onlyHandler(dao) {
        extraRate = _extraRate;
    }

    function stake(uint _amount, uint _lockDuration) external nonReentrant() {
        address _user = msg.sender;
        Stake storage data = stakers[_user];
        require(data.lastTimestamp == 0, "LPStaking: ");
        require(_lockDuration >= minLockDuration, "LPStaking: ");
        require(IERC20(lpManager).balanceOf(_user) >= _amount, "LPStaking: ");
        require(_amount > 0, "LPStaking: "); 
        if(timeSharesPool == 0) lastUpdated = block.timestamp;

        uint _initShares = updateTimeSharesPool();
        timeSharesPool += _initShares;
        membersCount += 1;

        uint _userShare; 
        if(sharesPool > 0){
            _userShare = _amount * sharesPool / pool;
        } else {
            _userShare = _amount;
            initStake(); 
        }

        pool += _amount;
        sharesPool += _userShare;

        data.staked = _amount;
        data.amountShares = _userShare; 
        data.stakeStart = block.timestamp;
        data.lockDuration = _lockDuration;
        data.timeShares = _initShares;
        data.lastTimestamp = block.timestamp;

        IERC20(lpManager).safeTransferFrom(_user, address(this), _amount);
    }

    function collectRewards(bool _baseReward, bool _extraReward) external nonReentrant() {
        require(_baseReward || _extraReward, "LPStaking: ");
        address _user = msg.sender;
        Stake storage data = stakers[_user];
        require(data.lastTimestamp > 0, "LPStaking: ");
        updateTimeSharesPool();
        updateUserTimeShares(_user);

        if(_baseReward){
            uint _baseRewardAmount = calculateUserBaseReward(_user);
            require(IERC20(lpManager).balanceOf(address(this)) >= _baseRewardAmount, "LPStaking: ");
            uint _sharePoolDecrease = _baseRewardAmount * sharesPool / pool;
            data.amountShares -= _sharePoolDecrease; 
            sharesPool -= _sharePoolDecrease;
            pool -= _baseRewardAmount;
            IERC20(lpManager).safeTransfer(_user, _baseRewardAmount);
        }

        if(_extraReward){
            uint _extraRewardAmount = calculateUserExtraReward(_user);
            require(IERC20(rewardToken).balanceOf(address(this)) >= _extraRewardAmount, "LPStaking: ");
            extraRewardPool -= _extraRewardAmount;
            data.extraRewardClaimed += _extraRewardAmount;
            IERC20(rewardToken).safeTransfer(_user, _extraRewardAmount);
        }
    }

    function compoundRewards(bool _baseReward, bool _extraReward) external nonReentrant() {

    }

    function unstake() external nonReentrant() {
        address _user = msg.sender;
        Stake storage data = stakers[_user];
        require(data.lastTimestamp > 0, "LPStaking: ");
        require(block.timestamp >= data.stakeStart + data.lockDuration, "LPStaking: ");
        
        uint _amount = calculateUserAmount(_user);

        require(IERC20(lpManager).balanceOf(address(this)) >= _amount, "LPStaking: ");

        updateTimeSharesPool();
        updateUserTimeShares(_user);

        timeSharesPool -= data.timeShares;
        membersCount -= 1;

        pool -= _amount;
        sharesPool -= data.amountShares;

        delete stakers[_user];

        IERC20(lpManager).safeTransfer(_user, _amount);
    }

    function addRewards(uint _amount, uint _extraAmount) external nonReentrant() {
        require(_amount > 0 || _extraAmount > 0, "LPStaking: "); 
        require(IERC20(lpManager).balanceOf(msg.sender) >= _amount, "LPStaking: ");
        require(IERC20(rewardToken).balanceOf(msg.sender) >= _extraAmount, "LPStaking: ");
        pool += _amount;
        extraRewardPool += _extraAmount;
        IERC20(lpManager).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _extraAmount);
    }

    function updateUserTimeShares(address _user) public returns(uint) {
        Stake storage data = stakers[_user];
        data.timeShares = preUpdateUserTimeShares(_user);
        data.lastTimestamp = block.timestamp;

        return data.timeShares;
    }

    function updateTimeSharesPool() public returns(uint) {
        timeSharesPool = preUpdateTimeSharesPool();
        initShares = preUpdateInitShares();
        lastUpdated = block.timestamp;

        return initShares;
    }

    function preUpdateInitShares() public view returns(uint) {
        return initShares - (block.timestamp - lastUpdated);
    }

    function preUpdateTimeSharesPool() public view returns(uint) {
        return timeSharesPool + membersCount * (block.timestamp - lastUpdated);
    }

    function preUpdateUserTimeShares(address _user) public view returns(uint) {
        Stake memory data = stakers[_user];
        if(data.lastTimestamp == 0) return 0; 
        return data.timeShares + (block.timestamp - data.lastTimestamp);
    }

    function calculateUserBaseReward(address _user) public view returns(uint) {
        return calculateUserAmount(_user) - stakers[_user].staked;
    }

    function calculateUserExtraReward(address _user) public view returns(uint) {
        Stake memory data = stakers[_user];
        return calculateRewardIncrease(data.staked, calculateUserRate(_user), data.lastTimestamp) - data.extraRewardClaimed;
    }

    function calculateUserAmount(address _user) public view returns(uint) {
        return stakers[_user].amountShares * pool / sharesPool;
    }

    function calculateUserRate(address _user) public view returns(uint) {
        return preUpdateUserTimeShares(_user) * extraRate / preUpdateTimeSharesPool();
    } 

    function calculateRewardIncrease(uint _staked, uint _rate, uint _lastUpdate) internal view returns(uint) {
        return (_staked * _rate * ((block.timestamp - _lastUpdate) * Math.ACCURACY / Math.ONE_YEAR)) / Math.DOUBLE_ACC;
    }

    function initStake() internal {
        Stake storage data = stakers[address(this)];
        sharesPool = Math.INIT_LOCK_AMOUNT;
        data.amountShares = Math.INIT_LOCK_AMOUNT;
        data.stakeStart = Math.DOUBLE_ACC;
        data.lockDuration = Math.DOUBLE_ACC;
        data.timeShares = Math.INIT_LOCK_AMOUNT;
        data.lastTimestamp = Math.DOUBLE_ACC;
    }
}