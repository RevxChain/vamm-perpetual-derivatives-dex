// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Governable {

    address public gov;
    address public dao;
    address public controller;

    event NewGov(address newGov, uint time);
    event NewDao(address newDao, uint time);
    event NewController(address newController, uint time);

    modifier validateAddress(address target) {
        require(target != address(0) && target != address(this), "Governable: invalid address");
        _;
    }

    modifier onlyHandler(address handler) {
        require(msg.sender == handler, "Governable: invalid handler");
        _;
    }

    modifier onlyHandlers() {
        require(msg.sender == gov || msg.sender == dao, "Governable: invalid handler");
        _;
    }

    constructor() {
        _setGov(msg.sender);
        _setDao(msg.sender); 
    }

    function setGov(address newGov) external onlyHandlers() {
        _setGov(newGov);
    }

    function setDao(address newDao) external onlyHandler(dao) {
        _setDao(newDao);
    }

    function _setGov(address newGov) internal validateAddress(newGov) {
        gov = newGov;

        emit NewGov(newGov, block.timestamp);
    }

    function _setDao(address newDao) internal validateAddress(newDao) {
        dao = newDao;

        emit NewDao(newDao, block.timestamp);
    }

    function _setController(address newController) internal validateAddress(newController) {
        controller = newController;

        emit NewController(newController, block.timestamp);
    }
}