// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract ImplementationSlot {

    address public implementation;
    address public vault;
    address public stable;
    address public positionsTracker;

    string public strategy;

    bool public isInitialized;
    bool public usageEnabled;
    bool public autoUsageEnabled;
    bool public manualUsageEnabled;
    bool public totalPositionsConsider;
}