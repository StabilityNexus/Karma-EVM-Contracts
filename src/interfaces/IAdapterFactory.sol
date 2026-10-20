// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

interface IAdapterFactory {
    function createAdapter(bytes calldata params) external returns (address adapter);
}
