// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockBaseToken — Simple ERC20 for testing
contract MockBaseToken is ERC20 {
    constructor() ERC20("Mock Base", "BASE") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockCoin — Simulates Coin with priceSell() and reserve tracking
/// @dev   The "reserve" is simply the baseToken balance held by this contract.
contract MockCoin is ERC20 {
    IERC20 public immutable asset;
    uint256 public constant DENOMINATOR = 100_000;

    constructor(string memory name, string memory symbol, address _asset) ERC20(name, symbol) {
        asset = IERC20(_asset);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /// @notice Simulates Coin.priceSell() = reserve * DENOMINATOR / supply
    function priceSell() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return DENOMINATOR;
        return (asset.balanceOf(address(this)) * DENOMINATOR) / supply;
    }
}

/// @title MockPredictionPool — Simulates PredictionPool for Karma testing
contract MockPredictionPool {
    IERC20 public baseToken;
    address public bullCoin;
    address public bearCoin;

    constructor(address _baseToken, address _bullCoin, address _bearCoin) {
        baseToken = IERC20(_baseToken);
        bullCoin = _bullCoin;
        bearCoin = _bearCoin;
    }
}
