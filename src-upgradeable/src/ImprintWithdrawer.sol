// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title ImprintWithdrawer
 * @notice Handles withdrawals for Imprint contract to reduce contract size
 */
contract ImprintWithdrawer is OwnableUpgradeable {
    
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error NoETHToWithdraw();
    error ETHTransferFailed();
    error NoTokensToWithdraw();
    error TokenTransferFailed();

    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);
    }

    /*─────────────── Withdrawals ───────────────*/
    function withdraw(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoETHToWithdraw();
        
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert ETHTransferFailed();
        
        emit ETHWithdrawn(to, balance);
    }

    function withdrawToken(address token, address to) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoTokensToWithdraw();
        
        if (!IERC20(token).transfer(to, balance)) revert TokenTransferFailed();
        
        emit ERC20Withdrawn(token, to, balance);
    }
}