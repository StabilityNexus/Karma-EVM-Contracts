// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AccumulatorVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public dev;
    address public devFeeReceiver;
    address public pendingDev;

    error ZeroAddress();
    error OnlyDev();
    error NoPendingDev();
    error NotPendingDev();

    event DevFeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    event DevTransferProposed(address indexed currentDev, address indexed proposedDev);
    event DevTransferred(address indexed previousDev, address indexed newDev);
    event TokenFlushed(address indexed token, address indexed receiver, uint256 amount);

    constructor(address initialDev, address initialDevFeeReceiver) {
        if (initialDev == address(0) || initialDevFeeReceiver == address(0)) revert ZeroAddress();
        dev = initialDev;
        devFeeReceiver = initialDevFeeReceiver;
    }

    modifier onlyDev() {
        if (msg.sender != dev) revert OnlyDev();
        _;
    }

    function setDevFeeReceiver(address newReceiver) external onlyDev {
        if (newReceiver == address(0)) revert ZeroAddress();
        address previousReceiver = devFeeReceiver;
        devFeeReceiver = newReceiver;
        emit DevFeeReceiverUpdated(previousReceiver, newReceiver);
    }

    function proposeDevTransfer(address newDev) external onlyDev {
        if (newDev == address(0)) revert ZeroAddress();
        pendingDev = newDev;
        emit DevTransferProposed(dev, newDev);
    }

    function acceptDevTransfer() external {
        if (pendingDev == address(0)) revert NoPendingDev();
        if (msg.sender != pendingDev) revert NotPendingDev();

        address previousDev = dev;
        dev = msg.sender;
        delete pendingDev;
        emit DevTransferred(previousDev, msg.sender);
    }

    function flushToken(address token) external onlyDev nonReentrant returns (uint256 amount) {
        if (token == address(0)) revert ZeroAddress();
        amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(devFeeReceiver, amount);
        emit TokenFlushed(token, devFeeReceiver, amount);
    }
}
