// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IGovernable {

    function gov() external view returns(address);
    function dao() external view returns(address);
    function controller() external view returns(address);

    function setGov(address _gov) external;

    function setDao(address _dao) external;

}