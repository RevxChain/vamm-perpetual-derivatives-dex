// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Governable {

    address public gov;
    address public dao;

    event NewGov(address newGov, uint time);
    event NewDao(address newDao, uint time);

    modifier validateAddress(address _address) {
        require(_address != address(0) && _address != address(this), "Governable: invalid address");
        _;
    }

    modifier onlyHandler(address _handler) {
        require(msg.sender == _handler, "Governable: invalid handler");
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

    function setGov(address _gov) external onlyHandlers() validateAddress(_gov) {
        gov = _gov;

        emit NewGov(_gov, block.timestamp);
    }

    function setDao(address _dao) external onlyHandler(dao) validateAddress(_dao) {
        dao = _dao;

        emit NewDao(_dao, block.timestamp);
    }
}
