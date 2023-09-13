// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
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

    function deposit(uint _tokenId, uint _lockDuration) external nonReentrant() {
        address _user = msg.sender;
        Stake storage stake = staked[_tokenId]; 
        validateOwnership(_user, _tokenId, _lockDuration, true);
        
        (, , bool _liquidator, ) = IUtilityToken(utilityToken).getUtility(_tokenId);
        if(_liquidator) IMarketRouter(marketRouter).setLiquidatorUtility(_user, true);

        owners[_user] = _tokenId;
        stake.owner = _user;
        stake.depositTimestamp = block.timestamp;
        stake.lockDuration = _lockDuration;
        
        IERC721(utilityToken).safeTransferFrom(_user, address(this), _tokenId);
    }

    function withdraw(uint _tokenId, address _receiver) external nonReentrant() {
        address _user = msg.sender; 
        validateOwnership(_user, _tokenId, 0, false);

        (, , bool _liquidator, ) = IUtilityToken(utilityToken).getUtility(_tokenId);
        if(_liquidator) IMarketRouter(marketRouter).setLiquidatorUtility(_user, false);

        IERC721(utilityToken).safeTransferFrom(address(this), _receiver, _tokenId);

        delete staked[_tokenId];
        delete owners[_user];
    }

    function getUserUtility(address _user) external view returns(
        bool staker, 
        uint maxLeverage, 
        bool operatingFee, 
        bool liquidator, 
        uint votePower
    ) {
        uint _tokenId = owners[_user];
        if(staked[_tokenId].owner != _user) return(false, 0, false, false, 0);
        staker = true;

        (maxLeverage, operatingFee, liquidator, votePower) = IUtilityToken(utilityToken).getUtility(_tokenId);
    }

    function validateOwnership(address _user, uint _tokenId, uint _lock, bool _deposit) internal view {
        Stake memory stake = staked[_tokenId]; 
        if(_deposit){
            require(
                stake.owner == address(0) && 
                owners[_user] == 0 && 
                stake.depositTimestamp == 0, 
                "UtilityStorage: deposited already"
            );
            require(IERC721(utilityToken).ownerOf(_tokenId) == _user, "UtilityStorage: you are not an owner");
            require(MAX_LOCK_DURATION >= _lock && _lock >= MIN_LOCK_DURATION , "UtilityStorage: invalid lockDuration");
        } else {
            require(
                stake.owner == _user && 
                owners[_user] == _tokenId && 
                stake.depositTimestamp > 0 && 
                IERC721(utilityToken).ownerOf(_tokenId) == address(this), 
                "UtilityStorage: you are not an owner"
            );
            require(block.timestamp >= stake.depositTimestamp + stake.lockDuration, "UtilityStorage: locked");
        }
    }
}