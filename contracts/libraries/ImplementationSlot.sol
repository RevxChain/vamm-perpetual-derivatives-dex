// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract ImplementationSlot {

    /// @custom:storage-location erc7201:RevxChain.storage.ImplementationSlot.Main
    struct Main {
        address _implementation;
        address _vault;
        address _stable;
        address _positionsTracker;

        string _strategy;

        bool _isInitialized;
        bool _active;
        bool _usageEnabled;
        bool _autoUsageEnabled;
        bool _manualUsageEnabled;
        bool _totalPositionsConsider;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("RevxChain.storage.ImplementationSlot.Main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ImplementationSlotMainStorageLocation = 0xaa204f4e167693e8e68777bdb4613da818053e65e35aebe4519379c8503ab300;

    function implementation() public view returns(address) {
        Main storage $ = getImplementationSlotMain();
        return $._implementation;
    }

    function vault() public view returns(address) {
        Main storage $ = getImplementationSlotMain();
        return $._vault;
    }

    function stable() public view returns(address) {
        Main storage $ = getImplementationSlotMain();
        return $._stable;
    }

    function positionsTracker() public view returns(address) {
        Main storage $ = getImplementationSlotMain();
        return $._positionsTracker;
    }

    function strategy() public view returns(string memory) {
        Main storage $ = getImplementationSlotMain();
        return $._strategy;
    }

    function isInitialized() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._isInitialized;
    }

    function active() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._active;
    }

    function usageEnabled() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._usageEnabled;
    }

    function autoUsageEnabled() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._autoUsageEnabled;
    }

    function manualUsageEnabled() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._manualUsageEnabled;
    }

    function totalPositionsConsider() public view returns(bool) {
        Main storage $ = getImplementationSlotMain();
        return $._totalPositionsConsider;
    }

    function getImplementationSlotMain() private pure returns(Main storage $) {
        assembly {
            $.slot := ImplementationSlotMainStorageLocation
        }
    }

    function _setImplementation(address newImplementation) internal {
        Main storage $ = getImplementationSlotMain();
        $._implementation = newImplementation;
    }

    function _setVault(address newVault) internal {
        Main storage $ = getImplementationSlotMain();
        $._vault = newVault;
    }

    function _setStable(address newStable) internal {
        Main storage $ = getImplementationSlotMain();
        $._stable = newStable;
    }

    function _setPositionsTracker(address newPositionsTracker) internal {
        Main storage $ = getImplementationSlotMain();
        $._positionsTracker = newPositionsTracker;
    }

    function _setStrategy(string memory newStrategy) internal {
        Main storage $ = getImplementationSlotMain();
        $._strategy = newStrategy;
    }

    function _setIsInitialized(bool newIsInitialized) internal {
        Main storage $ = getImplementationSlotMain();
        $._isInitialized = newIsInitialized;
    }

    function _setActive(bool enableActive) internal {
        Main storage $ = getImplementationSlotMain();
        $._active = enableActive;
    }

    function _setUsageEnabled(bool newUsageEnabled) internal {
        Main storage $ = getImplementationSlotMain();
        $._usageEnabled = newUsageEnabled;
    }

    function _setAutoUsageEnabled(bool newAutoUsageEnabled) internal {
        Main storage $ = getImplementationSlotMain();
        $._autoUsageEnabled = newAutoUsageEnabled;
    }

    function _setManualUsageEnabled(bool newManualUsageEnabled) internal {
        Main storage $ = getImplementationSlotMain();
        $._manualUsageEnabled = newManualUsageEnabled;
    }

    function _setTotalPositionsConsider(bool newTotalPositionsConsider) internal {
        Main storage $ = getImplementationSlotMain();
        $._totalPositionsConsider = newTotalPositionsConsider;
    }

}