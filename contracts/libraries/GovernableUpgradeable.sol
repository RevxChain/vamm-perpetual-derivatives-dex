// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract GovernableUpgradeable {

    /// @custom:storage-location erc7201:RevxChain.storage.GovernableUpgradeable.Addresses
    struct Addresses {
        address _gov;
        address _dao;
        address _controller;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("RevxChain.storage.GovernableUpgradeable.Addresses")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GovernableUpgradeableAddressesStorageLocation = 0xf68a11b203d9dad6bb4b3973f70a36c16c6ed774dde501eeb944985ee4764c00;

    event NewGov(address indexed newGov, uint time);
    event NewDao(address indexed newDao, uint time);
    event NewController(address indexed newController, uint time);

    modifier validateAddress(address target) {
        require(target != address(0) && target != address(this), "GovernableUpgradeable: invalid address");
        _;
    }

    modifier onlyHandler(address handler) {
        require(msg.sender == handler, "GovernableUpgradeable: invalid handler");
        _;
    }

    modifier onlyHandlers() {
        require(msg.sender == gov() || msg.sender == dao(), "GovernableUpgradeable: invalid handler");
        _;
    }

    constructor() {
        _setGov(msg.sender); 
        _setDao(msg.sender);
    }

    function setGov(address newGov) external onlyHandlers() validateAddress(newGov) {
        _setGov(newGov);
    }

    function setDao(address newDao) external onlyHandler(dao()) validateAddress(newDao) {
        _setDao(newDao);
    }

    function gov() public view returns(address) {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        return $._gov;
    }

    function dao() public view returns(address) {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        return $._dao;
    }

    function controller() public view returns(address) {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        return $._controller;
    }

    function getGovernableUpgradeableAddresses() private pure returns(Addresses storage $) {
        assembly {
            $.slot := GovernableUpgradeableAddressesStorageLocation
        }
    }

    function _setGov(address newGov) internal {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        $._gov = newGov;

        emit NewGov(newGov, block.timestamp);
    }

    function _setDao(address newDao) internal {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        $._dao = newDao;

        emit NewDao(newDao, block.timestamp);
    }

    function _setController(address newController) internal {
        Addresses storage $ = getGovernableUpgradeableAddresses();
        $._controller = newController;

        emit NewController(newController, block.timestamp);
    }
}