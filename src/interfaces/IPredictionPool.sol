// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPredictionPool {
    function baseToken() external view returns (IERC20);
    function bullCoin() external view returns (address);
    function bearCoin() external view returns (address);
    function rebalance() external;
}
