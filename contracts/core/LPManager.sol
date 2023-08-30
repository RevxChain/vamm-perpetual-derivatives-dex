// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "../libraries/Governable.sol";
import "./interfaces/IVault.sol";
import "../libraries/Math.sol";

contract LPManager is ERC20Burnable, Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint;
    
    address public vault;
    address public stable;
    address public positionsTracker;

    bool public isInitialized;

    constructor() ERC20("Vault Supply Token", "sToken") {}

    function initialize(
        address _vault, 
        address _stable,
        address _positionsTracker
    ) external onlyHandler(gov) {  
        require(!isInitialized, "LPManager: initialized");
        isInitialized = true;

        vault = _vault;
        stable = _stable;
        positionsTracker = _positionsTracker;
    }

    function addLiquidity(uint _underlyingAmount) external nonReentrant() {
        validateAmount(_underlyingAmount);
        uint _amount = _underlyingAmount.stableToPrecision();

        uint userShare; 
        if(totalSupply() > 0){
            userShare = _amount * totalSupply() / IVault(vault).poolAmount();
        } else {
            userShare = _amount.sqrt();
            _mint(vault, Math.INIT_LOCK_AMOUNT);
        }
        _mint(msg.sender, userShare);

        IVault(vault).increasePool(_amount);
        IERC20(stable).safeTransferFrom(msg.sender, vault, _underlyingAmount);
    }

    function removeLiquidity(uint _sTokenAmount) external nonReentrant() {
        validateAmount(_sTokenAmount);
        uint _underlyingAmount = calculateUnderlying(_sTokenAmount);

        _burn(msg.sender, _sTokenAmount);
 
        IVault(vault).decreasePool(msg.sender, _underlyingAmount.stableToPrecision(), _underlyingAmount);
    }

    function calculateUnderlying(uint _sTokenAmount) public view returns(uint underlyingAmount) {
        uint _stableAmount = _sTokenAmount * IVault(vault).poolAmount() / totalSupply();
        underlyingAmount = _stableAmount.precisionToStable();
    }

    function decimals() public override pure returns(uint8) {
        return 9;
    }

    function validateAmount(uint _amount) internal pure {
        require(_amount > 0, "LPManager: invalid amount");
    }
}