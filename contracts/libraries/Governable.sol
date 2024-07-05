// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Governable {

    address public gov;
    address public dao;
    address public controller;

    event NewGov(address newGov, uint time);
    event NewDao(address newDao, uint time);

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
        gov = msg.sender; 
        dao = msg.sender;

        emit NewGov(msg.sender, block.timestamp);
        emit NewDao(msg.sender, block.timestamp);
    }

    function setGov(address newGov) external onlyHandlers() validateAddress(newGov) {
        gov = newGov;

        emit NewGov(newGov, block.timestamp);
    }

    function setDao(address newDao) external onlyHandler(dao) validateAddress(newDao) {
        dao = newDao;

        emit NewDao(newDao, block.timestamp);
    }
}
