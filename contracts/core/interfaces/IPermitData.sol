// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPermitData {

    struct PermitData {
        uint deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

}