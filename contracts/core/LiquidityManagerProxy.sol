// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../libraries/ImplementationSlot.sol";

contract LiquidityManagerProxy is ImplementationSlot {

    constructor(address newImplementation) {
        _setImplementation(newImplementation);
    }

    fallback() external payable {
        address __implementation = implementation();
        assembly {
            if eq(calldataload(0), 0xa619486e00000000000000000000000000000000000000000000000000000000) {
                mstore(0, __implementation)
                return(0, 0x20)
            }
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), __implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}