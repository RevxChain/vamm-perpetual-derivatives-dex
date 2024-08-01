// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import "./IDebtor.sol";
import "./IOwnable2Step.sol";

interface IMultiWallet is IOwnable2Step, IDebtor, IERC1155Receiver, IERC721Receiver {

    function multiWalletMarketplace() external view returns(address);
    function whitelistEnabled() external view returns(bool);
    function paused() external view returns(bool);

    function nonces(address target) external view returns(uint);
    function blacklist(address executor) external view returns(bool);
    function whitelist(address executor) external view returns(bool);
    function signatureUsed(bytes calldata signature) external view returns(bool);

    struct CallData {
        address payable target; 
        uint ethValue;
        bytes data;
        uint deadline;
        bytes signature;
    }

    struct CallDataInternal {
        bytes signatureToRevoke; 
        address targetToIncrease;
        address executorToBlock;
        bool blockExecutor;
        bool enableWhitelist;
        address executorToRaise;
        bool raiseExecutor;
        bool pauseEnable;
        uint deadline;
        bytes signature;
    }

    function revokeSignature(bytes calldata signature) external;

    function increaseNonce(address target) external;

    function setBlacklist(address executor, bool set) external;

    function enableWhitelist(bool enable) external;

    function setWhitelist(address executor, bool set) external;

    function setPause(bool pauseEnable) external;

    function executeCall(CallData calldata $) external returns(bool success, bytes memory response);

    function executeInternalCall(CallDataInternal calldata $$) external;

    function externalCall(
        CallData calldata $, 
        bool successCheck
    ) external payable returns(bool success, bytes memory response);

    function executeLoan(CallData calldata $) external payable;

    function transferEther(
        address payable receiver, 
        uint amount,
        bool successCheck
    ) external returns(bool success, bytes memory response);

    function approveERC20(
        address token, 
        address spender, 
        uint amount
    ) external;

    function approveERC721(
        address token, 
        address spender, 
        uint tokenId
    ) external;

    function approveERC1155(
        address token, 
        address spender,
        bool setApprove
    ) external;

    function transferERC20(
        address token, 
        address receiver, 
        uint amount
    ) external;

    function transferFromERC20(
        address token, 
        address owner, 
        address receiver, 
        uint amount
    ) external;

    function transferERC721(
        address token, 
        address receiver, 
        uint tokenId
    ) external;

    function safeTransferFromERC721(
        address token, 
        address owner, 
        address receiver, 
        uint tokenId
    ) external;

    function safeTransferFromERC721Data(
        address token, 
        address owner, 
        address receiver, 
        uint tokenId,
        bytes calldata data
    ) external;

    function safeTransferFromERC1155(
        address token,
        address owner,
        address receiver,
        uint tokenId,
        uint amount,
        bytes calldata data
    ) external;

    function safeBatchTransferFromERC1155(
        address token,
        address owner,
        address receiver,
        uint[] calldata tokenIds,
        uint[] calldata amounts,
        bytes calldata data
    ) external;

    function createSellOrder(
        address paymentToken,
        uint price,
        address paymentReceiver,
        uint deadline
    ) external;

    function cancelSellOrder() external;

    function getERC20Balance(address token) external view returns(uint);

    function getERC721Balance(address token) external view returns(uint);

    function getERC1155Balance(address token, uint tokenId) external view returns(uint);

    function getSaleable() external view returns(bool result, address paymentToken, uint price);

    function getSignedHash(CallData memory $) external view returns(bytes32);

    function getHashPacked(
        address user, 
        address verifier,
        uint nonce,  
        uint chainId, 
        CallData memory $
    ) external pure returns(bytes32);

}