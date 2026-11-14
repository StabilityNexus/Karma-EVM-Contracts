// SPDX-License-Identifier: AEL
pragma solidity ^0.8.23;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// MockBaseToken — Simple ERC20 for testing
contract MockBaseToken is ERC20 {
    constructor() ERC20("Mock Base", "BASE") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// MockFeeOnTransferToken — Simulates fee-on-transfer token with configurable fees
contract MockFeeOnTransferToken is ERC20 {
    uint256 public feeBps = 100; // 1%
    bool public feeOnTransfer;
    bool public feeOnTransferFrom = true;
    address public exemptRecipient;
    uint256 public transferCount;
    uint256 public taxOnlyTransferIndex;

    constructor() ERC20("Mock FOT", "FOT") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFeeOnTransfer(bool enabled) external {
        feeOnTransfer = enabled;
    }

    function setFeeOnTransferFrom(bool enabled) external {
        feeOnTransferFrom = enabled;
    }

    function setExemptRecipient(address recipient) external {
        exemptRecipient = recipient;
    }

    function setTaxOnlyTransferIndex(uint256 index) external {
        taxOnlyTransferIndex = index;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        transferCount++;
        bool shouldTax = feeOnTransfer;
        if (taxOnlyTransferIndex > 0) {
            shouldTax = (transferCount == taxOnlyTransferIndex);
        }
        if (shouldTax) {
            uint256 fee = (amount * feeBps) / 10_000;
            _burn(msg.sender, fee);
            return super.transfer(to, amount - fee);
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool shouldTax = feeOnTransferFrom && to != exemptRecipient;
        if (shouldTax) {
            uint256 fee = (amount * feeBps) / 10_000;
            _burn(from, fee);
            return super.transferFrom(from, to, amount - fee);
        }
        return super.transferFrom(from, to, amount);
    }
}

// MockCoin — Simulates Coin with priceSell() and reserve tracking.
// The "reserve" is simply the baseToken balance held by this contract.
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

    // Simulates Coin.priceSell() = reserve * DENOMINATOR / supply
    function priceSell() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return DENOMINATOR;
        return (asset.balanceOf(address(this)) * DENOMINATOR) / supply;
    }
}

// MockPredictionPool — Simulates PredictionPool for Karma testing
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
