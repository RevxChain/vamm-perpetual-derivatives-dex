// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract StakedSupplyToken is ERC20Burnable {    

    address public immutable LPStaking;  

    constructor(address _LPStaking) ERC20("Staked Vault Supply Token", "stToken") {
        LPStaking = _LPStaking;
    }

    function mint(address _user, uint _amount) external {
        _mint(_user, _amount);
    }

    function decimals() public override pure returns(uint8) {
        return 9;
    }

    function _beforeTokenTransfer(address /*_from*/, address /*_to*/, uint /*_amount*/) internal view override {
        require(msg.sender == LPStaking, "StakedSupplyToken: forbidden");
    }
}