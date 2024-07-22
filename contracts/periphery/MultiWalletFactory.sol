// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./MultiWallet.sol";

import "./interfaces/IOwnable2Step.sol";

contract MultiWalletFactory {

    uint public totalWallets;

    address public immutable stable;
    address public immutable lpManager;
    address public immutable orderBook;
    address public immutable marketRouter;
    address public immutable vault;

    mapping(uint => address) public wallets;
    mapping(address => bool) public walletExist;

    constructor(
        address _stable, 
        address _lpManager,
        address _orderBook,
        address _marketRouter,
        address _vault
    ) {
        stable = _stable;
        lpManager = _lpManager;
        orderBook = _orderBook;
        marketRouter = _marketRouter;
        vault = _vault;
    }

    function createMultiWallet(address owner) external returns(address newMultiWallet) {
        bytes memory _bytecode = abi.encodePacked(
            type(MultiWallet).creationCode, 
            abi.encode(
                owner, 
                stable, 
                lpManager, 
                orderBook, 
                marketRouter, 
                vault
            )
        );

        bytes32 _salt = keccak256(abi.encodePacked(address(this), totalWallets));

        assembly {
            newMultiWallet := create2(0, add(_bytecode, 32), mload(_bytecode), _salt)
        }
    
        wallets[totalWallets] = newMultiWallet;
        walletExist[newMultiWallet] = true;
        totalWallets += 1;
    }

    function getWalletOwner(
        address multiWalletAddress
    ) external view returns(bool multiWalletExist, address currentOwner, address pendingOwner) {
        if(!walletExist[multiWalletAddress]) return(false, address(0), address(0));
        return (true, IOwnable2Step(multiWalletAddress).owner(), IOwnable2Step(multiWalletAddress).pendingOwner());
    }

}