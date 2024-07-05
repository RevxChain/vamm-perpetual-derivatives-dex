// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "../libraries/Governable.sol";

import "../core/interfaces/IMarketRouter.sol";
import "../tokens/interfaces/IUtilityToken.sol";

contract UtilityStorage is ERC721Holder, Governable, ReentrancyGuard {

    uint public constant MIN_LOCK_DURATION = 4 weeks;
    uint public constant MAX_LOCK_DURATION = 52 weeks;

    address public utilityToken;
    address public marketRouter;

    bool public isInitialized;

    mapping(address => uint) public owners;
    mapping(uint => Stake) public staked;

    struct Stake {
        address owner;
        uint depositTimestamp;
        uint lockDuration;
    }

    function initialize(address _utilityToken, address _marketRouter) external onlyHandler(gov) {
        require(!isInitialized, "UtilityStorage: initialized");
        isInitialized = true;

        utilityToken = _utilityToken; 
        marketRouter = _marketRouter;
    }

    function deposit(uint tokenId, uint lockDuration) external nonReentrant() {
        address _user = msg.sender;
        Stake storage stake = staked[tokenId]; 
        validateOwnership(_user, tokenId, lockDuration, true);
        
        (, , bool _liquidator, , ) = IUtilityToken(utilityToken).getUtility(tokenId);
        if(_liquidator) IMarketRouter(marketRouter).setLiquidatorUtility(_user, true);

        owners[_user] = tokenId;
        stake.owner = _user;
        stake.depositTimestamp = block.timestamp;
        stake.lockDuration = lockDuration;
        
        IERC721(utilityToken).safeTransferFrom(_user, address(this), tokenId);
    }

    function withdraw(uint tokenId, address receiver) external nonReentrant() {
        address _user = msg.sender; 
        validateOwnership(_user, tokenId, 0, false);

        (, , bool _liquidator, , ) = IUtilityToken(utilityToken).getUtility(tokenId);
        if(_liquidator) IMarketRouter(marketRouter).setLiquidatorUtility(_user, false);

        IERC721(utilityToken).safeTransferFrom(address(this), receiver, tokenId);

        delete staked[tokenId];
        delete owners[_user];
    }

    function getUserUtility(address user) external view returns(
        bool staker, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower,
        uint flashLoanFee
    ) {
        uint _tokenId = owners[user];
        if(staked[_tokenId].owner != user) return(false, 0, false, false, 0, 0);
        staker = true;

        (maxLeverage, operatingFee, liquidator, votePower, flashLoanFee) = IUtilityToken(utilityToken).getUtility(_tokenId);
    }

    function validateOwnership(address user, uint tokenId, uint lock, bool isDeposit) internal view {
        Stake memory stake = staked[tokenId]; 
        if(isDeposit){
            require(
                stake.owner == address(0) && 
                owners[user] == 0 && 
                stake.depositTimestamp == 0, 
                "UtilityStorage: deposited already"
            );
            require(IERC721(utilityToken).ownerOf(tokenId) == user, "UtilityStorage: you are not an owner");
            require(MAX_LOCK_DURATION >= lock && lock >= MIN_LOCK_DURATION , "UtilityStorage: invalid lockDuration");
        } else {
            require(
                stake.owner == user && 
                owners[user] == tokenId && 
                stake.depositTimestamp > 0 && 
                IERC721(utilityToken).ownerOf(tokenId) == address(this), 
                "UtilityStorage: you are not an owner"
            );
            require(block.timestamp >= stake.depositTimestamp + stake.lockDuration, "UtilityStorage: locked");
        }
    }
}