// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IImplementationSlot {

    function implementation() external view returns(address); 
    function vault() external view returns(address);
    function stable() external view returns(address);
    function positionsTracker() external view returns(address);
    function strategy() external view returns(string memory);
    function isInitialized() external view returns(bool);
    function active() external view returns(bool);
    function usageEnabled() external view returns(bool);
    function autoUsageEnabled() external view returns(bool);
    function manualUsageEnabled() external view returns(bool);
    function totalPositionsConsider() external view returns(bool);

}