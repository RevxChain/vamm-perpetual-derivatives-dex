// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILiquidityManagerProxy {

    function masterCopy() external view returns(address);

}

contract LiquidityManagerProxy {

    address internal implementation;

    constructor(address newImplementation) {
        implementation = newImplementation;
    }

    fallback() external payable {
        assembly {
            let _implementation := and(sload(0), 0xffffffffffffffffffffffffffffffffffffffff)
            if eq(calldataload(0), 0xa619486e00000000000000000000000000000000000000000000000000000000) {
                mstore(0, _implementation)
                return(0, 0x20)
            }
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), _implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}