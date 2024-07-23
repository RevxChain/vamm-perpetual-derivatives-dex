// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./Debtor.sol";

import "./interfaces/IMultiWalletMarketplace.sol";

contract MultiWallet is Debtor, Pausable, ERC1155Holder, ERC721Holder, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    uint public constant SIGNATURE_LENGTH = 65;

    address public immutable multiWalletMarketplace;

    bool public whitelistEnabled;

    mapping(address => uint) public nonces;
    mapping(address => bool) public blacklist;
    mapping(address => bool) public whitelist;
    mapping(bytes => bool) public signatureUsed;

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

    constructor(
        address owner,
        address stable, 
        address lpManager,
        address orderBook,
        address marketRouter,
        address vault,
        address walletMarketplace
    ) Debtor(vault) {
        _transferOwnership(owner);

        IERC20(stable).forceApprove(lpManager, type(uint256).max);
        IERC20(stable).forceApprove(orderBook, type(uint256).max);
        IERC20(stable).forceApprove(marketRouter, type(uint256).max);

        multiWalletMarketplace = walletMarketplace;
    }

    receive() external payable override {
        // event placeholder 
    }

    function revokeSignature(bytes calldata signature) external onlyOwner() {
        _revokeSignature(signature);
    }

    function increaseNonce(address target) external onlyOwner() {
        _increaseNonce(target);
    }

    function setBlacklist(address executor, bool set) external onlyOwner() {
        _setBlacklist(executor, set);
    }

    function enableWhitelist(bool enable) external onlyOwner() {
        _enableWhitelist(enable);
    }

    function setWhitelist(address executor, bool set) external onlyOwner() {
        _setWhitelist(executor, set);
    }

    function setPause(bool pauseEnable) external onlyOwner() {
        _setPause(pauseEnable);
    }
    
    function executeCall(CallData calldata $) external nonReentrant() returns(bool success, bytes memory response) {   
        _ensure($.deadline, $.signature);
        _pendingOwnerForbidden();
        _ethBalanceCheck($.ethValue);

        uint _cachedNonce = nonces[$.target];
        bytes32 _hashedParams = getHashPacked(
            owner(), 
            msg.sender, 
            address(this), 
            _cachedNonce, 
            block.chainid, 
            $
        ).toEthSignedMessageHash();

        require(_hashedParams.recover($.signature) == owner(), "MultiWallet: invalid singer");

        nonces[$.target] += 1;
        signatureUsed[$.signature] = true;

        (success, response) = $.target.call{value: $.ethValue}($.data); 
    }

    function executeInternalCall(CallDataInternal calldata $$) external nonReentrant() {
        _ensure($$.deadline, $$.signature);
        _pendingOwnerForbidden();

        CallData memory $ = CallData({
            target: payable(address(this)),
            ethValue: 0,
            data: bytes.concat(keccak256(abi.encode(
                "0x16c55483", 
                $$.signatureToRevoke, 
                $$.targetToIncrease, 
                $$.executorToBlock, 
                $$.blockExecutor, 
                $$.enableWhitelist,
                $$.executorToRaise,
                $$.raiseExecutor,
                $$.pauseEnable
            ))),
            deadline: $$.deadline, 
            signature: $$.signature
        });

        uint _cachedNonce = nonces[address(this)];
        bytes32 _hashedParams = getHashPacked(
            owner(), 
            msg.sender, 
            address(this), 
            _cachedNonce, 
            block.chainid, 
            $
        ).toEthSignedMessageHash();

        require(_hashedParams.recover($$.signature) == owner(), "MultiWallet: invalid singer");

        nonces[address(this)] += 1;
        signatureUsed[$$.signature] = true;

        if($$.signatureToRevoke.length > 0) _revokeSignature($$.signatureToRevoke);
        if($$.targetToIncrease != address(0)) _increaseNonce($$.targetToIncrease);
        if($$.executorToBlock != address(0)) _setBlacklist($$.executorToBlock, $$.blockExecutor);
        if($$.enableWhitelist != whitelistEnabled) _enableWhitelist($$.enableWhitelist);
        if($$.executorToRaise != address(0)) _setWhitelist($$.executorToRaise, $$.raiseExecutor);
        if($$.pauseEnable != paused()) _setPause($$.pauseEnable);
    }

    function externalCall(
        CallData calldata $, 
        bool successCheck
    ) external payable nonReentrant() onlyOwner() returns(bool success, bytes memory response) {
        _pendingOwnerForbidden();
        _ethBalanceCheck($.ethValue);

        (success, response) = $.target.call{value: $.ethValue}($.data); 

        if(successCheck) require(success, "MultiWallet: external call failed");
    }

    function loan(uint amount, bytes calldata data) public payable override onlyOwner() {
        _pendingOwnerForbidden();
        super.loan(amount, data);
    }

    function executeLoan(CallData calldata $) external payable nonReentrant() {   
        _ensure($.deadline, $.signature);
        _pendingOwnerForbidden();
        require($.target == vault, "MultiWallet: invalid target");

        uint _cachedNonce = nonces[$.target];
        bytes32 _hashedParams = getHashPacked(
            owner(), 
            msg.sender, 
            address(this), 
            _cachedNonce, 
            block.chainid, 
            $
        ).toEthSignedMessageHash();

        require(_hashedParams.recover($.signature) == owner(), "MultiWallet: invalid singer");

        nonces[$.target] += 1;
        signatureUsed[$.signature] = true;

        super.loan($.ethValue, $.data);   
    }

    function executeFlashLoan(uint amount, uint fee, bytes calldata data) public override {
        executeFlashLoanCheck(amount, fee);

        address payable _target = payable(address(bytes20(data[0:20])));
        uint _ethValue =  uint80(bytes10(data[20:30]));

        _ethBalanceCheck(_ethValue);

        IERC20(stable).safeTransfer(_target, uint48(bytes6(data[30:36])));

        (bool _success, ) = _target.call{value: _ethValue}(data[36:]);

        require(_success, "MultiWallet: flashloan call failed");
        require(IERC20(stable).balanceOf(address(this)) >= amount + fee, "MultiWallet: invalid output balance");
        IERC20(stable).forceApprove(vault, amount + fee);
    }

    function transferEther(
        address payable receiver, 
        uint amount,
        bool successCheck
    ) external onlyOwner() returns(bool success, bytes memory response) {
        _pendingOwnerForbidden();
        _ethBalanceCheck(amount);

        (success, response) = receiver.call{value: amount}(""); 

        if(successCheck) require(success, "MultiWallet: ETH transfer failed");
    }

    function approveERC20(
        address token, 
        address spender, 
        uint amount
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC20(token).forceApprove(spender, amount);
    }

    function approveERC721(
        address token, 
        address spender, 
        uint tokenId
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC721(token).approve(spender, tokenId);
    }

    function approveERC1155(
        address token, 
        address spender,
        bool setApprove
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC1155(token).setApprovalForAll(spender, setApprove);
    }

    function transferERC20(
        address token, 
        address receiver, 
        uint amount
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC20(token).safeTransfer(receiver, amount);
    }

    function transferFromERC20(
        address token, 
        address owner, 
        address receiver, 
        uint amount
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC20(token).safeTransferFrom(owner, receiver, amount);
    }

    function transferERC721(
        address token, 
        address receiver, 
        uint tokenId
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC721(token).safeTransferFrom(address(this), receiver, tokenId);
    }

    function safeTransferFromERC721(
        address token, 
        address owner, 
        address receiver, 
        uint tokenId
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC721(token).safeTransferFrom(owner, receiver, tokenId);
    }

    function safeTransferFromERC721Data(
        address token, 
        address owner, 
        address receiver, 
        uint tokenId,
        bytes calldata data
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC721(token).safeTransferFrom(owner, receiver, tokenId, data);
    }

    function safeTransferFromERC1155(
        address token,
        address owner,
        address receiver,
        uint tokenId,
        uint amount,
        bytes calldata data
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC1155(token).safeTransferFrom(owner, receiver, tokenId, amount, data);
    }

    function safeBatchTransferFromERC1155(
        address token,
        address owner,
        address receiver,
        uint[] calldata tokenIds,
        uint[] calldata amounts,
        bytes calldata data
    ) external onlyOwner() {
        _pendingOwnerForbidden();
        IERC1155(token).safeBatchTransferFrom(owner, receiver, tokenIds, amounts, data);
    }

    function withdraw(
        address token, 
        uint amount, 
        address payable receiver
    ) public override onlyOwner() {
        _pendingOwnerForbidden();
        if(token == address(0)) _ethBalanceCheck(amount);
        super.withdraw(token, amount, receiver);
    }

    function createSellOrder(
        address paymentToken,
        uint price,
        address paymentReceiver,
        uint deadline
    ) external onlyOwner() {
        super.transferOwnership(multiWalletMarketplace);

        require(
            IMultiWalletMarketplace(multiWalletMarketplace).createOrder(paymentToken, price, paymentReceiver, deadline), 
            "MultiWallet: create order failed"
        );
    }

    function cancelSellOrder() external onlyOwner() {
        require(IMultiWalletMarketplace(multiWalletMarketplace).cancelOrder(), "MultiWallet: cancel order failed");

        super.transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public override onlyOwner() {
        _clearOrder();

        super.transferOwnership(newOwner);
    }

    function acceptOwnership() public override {
        super.acceptOwnership();

        _clearOrder();
    }

    function renounceOwnership() public override onlyOwner() {
        revert("MultiWallet: renounce forbidden"); 
    }

    function getERC20Balance(address token) external view returns(uint) {
        return IERC20(token).balanceOf(address(this));
    }

    function getERC721Balance(address token) external view returns(uint) {
        return IERC721(token).balanceOf(address(this));
    }

    function getERC1155Balance(address token, uint tokenId) external view returns(uint) {
        return IERC1155(token).balanceOf(address(this), tokenId);
    }

    function getSaleable() external view returns(bool result, address paymentToken, uint price) {
        price = IMultiWalletMarketplace(multiWalletMarketplace).orders(address(this)).price;
        paymentToken = IMultiWalletMarketplace(multiWalletMarketplace).orders(address(this)).paymentToken;
        return (price > 0, paymentToken, price);
    }

    function getHashPacked(
        address user, 
        address executor,
        address verifier,
        uint nonce,  
        uint chainId, 
        CallData memory $
    ) public pure returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                user, 
                executor, 
                verifier, 
                nonce, 
                chainId,
                $.target, 
                $.ethValue, 
                $.data, 
                $.deadline
            )
        );
    }

    function _revokeSignature(bytes calldata signature) internal {
        signatureUsed[signature] = true;
    }

    function _increaseNonce(address target) internal {
        nonces[target] += 1;
    }

    function _setBlacklist(address executor, bool set) internal {
        blacklist[executor] = set;
    }

    function _enableWhitelist(bool enable) internal { 
        whitelistEnabled = enable;
    }

    function _setWhitelist(address executor, bool set) internal {
        whitelist[executor] = set;
    }

    function _setPause(bool pauseEnable) internal {
        pauseEnable ? _pause() : _unpause();
    }

    function _clearOrder() internal {
        if(
            msg.sender != multiWalletMarketplace && 
            IMultiWalletMarketplace(multiWalletMarketplace).orders(address(this)).price > 0
        ) {
            require(IMultiWalletMarketplace(multiWalletMarketplace).cancelOrder(), "MultiWallet: clear order failed");
        }
    }

    function _ensure(uint deadline, bytes calldata signature) internal view {
        _requireNotPaused();
        require(deadline >= block.timestamp, "MultiWallet: expired");
        require(signature.length == SIGNATURE_LENGTH, "MultiWallet: invalid signature length");
        require(!signatureUsed[signature], "MultiWallet: signature used");
        require(!blacklist[msg.sender], "MultiWallet: blacklisted executor");
        if(whitelistEnabled) require(whitelist[msg.sender], "MultiWallet: not whitelisted executor");
    }

    function _pendingOwnerForbidden() internal view {
        require(pendingOwner() == address(0), "MultiWallet: pending owner forbidden");
    }

    function _ethBalanceCheck(uint amount) internal view {
        require(address(this).balance >= amount, "MultiWallet: invalid eth balance");
    }

}