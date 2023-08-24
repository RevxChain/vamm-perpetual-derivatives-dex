// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFastPriceFeed {

    function getPrice(address _indexToken, uint _referencePrice) external view returns(uint);
    
}