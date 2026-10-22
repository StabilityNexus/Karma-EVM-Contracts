# Remediations of Security Review Findings

Review date and time: 2026-10-22T19:05:55Z

## Remediations

### Remediation of Finding 1: Flash-loan oracle manipulation via flash-loaned coin balances

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Added `minHoldBlocks` immutable parameter to Karma contract (defaults to 1 block). Added `lastBalanceChangeBlock` mapping and `recordBalanceChange()` function callable by bull/bear Coin contracts. `submitPrice()` now reverts with `BalanceTooRecent()` if the caller's balance changed within the minimum hold window. Updated KarmaAdapterFactory and deploy script to support the new parameter.

### Remediation of Finding 2: Rebalance can be called by anyone to front-run oracle updates

This finding is documented as a deliberate design choice (Note 1 in the review). The public `rebalance()` is intentional for permissionless operation. No code change made.

### Remediation of Finding 3: Stale Chainlink price accepted without staleness check

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Added `maxStaleness` immutable parameter to ChainlinkOracle constructor (defaults to 3600 seconds / 1 hour). Both `readValue()` and `latestRoundData()` now revert with `StalePrice()` if `block.timestamp - updatedAt > maxStaleness`. Updated ChainlinkAdapterFactory to accept and cache by `(priceFeed, maxStaleness)` key.

### Remediation of Finding 4: Missing roundId >= answeredInRound check in Chainlink oracle

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Added `if (answeredInRound < roundId) revert StalePrice();` check in both `readValue()` and `latestRoundData()` in ChainlinkOracle.sol.

### Remediation of Finding 5: Coin.buy() price calculation uses Rounding.Ceil

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Changed `Math.mulDiv(..., Math.Rounding.Ceil)` to `Math.mulDiv(...)` (default Floor rounding) in `Coin.buy()` line 175–177, so the buyer never receives more coins than the deposited assets strictly justify.

### Remediation of Finding 6: AccumulatorVault.flushToken() reverts on zero balance

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Added `if (amount == 0) return 0;` early return in `flushToken()` before the `safeTransfer` call.

### Remediation of Finding 7: Karma.latestRoundData() unsafe uint256-to-int256 cast

- [x] This remediation implements the security review's recommendation for this finding.
- [ ] This remediation addresses the finding in a way that differs from the security review's recommendation.

Remediation commits:
- [2a25630](https://github.com/StabilityNexus/Karma-EVM-Contracts/commit/2a256304a06f4e99f92da0f0892692526d8b77e4)

Description: Added `if (price > uint256(type(int256).max)) revert PriceOutOfBounds();` bounds check in `latestRoundData()` before the `int256(price)` cast.

## Non-remediated findings

### Finding 2: Rebalance can be called by anyone to front-run oracle updates

This finding was not remediated because `rebalance()` is intentionally public as a documented design choice for permissionless operation. Both `Coin.buy()` and `Coin.sell()` call it via the `IPoolRebalance` interface, and removing public access would break the contract's core functionality. The MEV risk is an accepted trade-off.
