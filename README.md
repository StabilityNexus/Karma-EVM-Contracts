<div align="center">
  <h1>Karma Protocol</h1>
  <p><strong>Self-sovereign, fully on-chain prediction-market price oracle</strong></p>
</div>

[![License: AEL](https://img.shields.io/badge/License-AEL-green.svg)](LICENSE)
[![Stability Nexus](https://img.shields.io/badge/Stability-Nexus-228B22?style=flat)](https://stability.nexus/)

---

## Overview

Traditional prediction markets and DeFi protocols depend on external oracles (e.g. Chainlink) to determine settlement prices. External oracles introduce third-party trust assumptions, delay risks, outage liabilities, and off-chain dependencies.

**Karma Protocol** eliminates external oracles. It is an on-chain, participant-driven price oracle where the market participants themselves discover and report prices. Manipulation is prevented using **economic neutrality weighting**: a participant's influence is proportional to their neutrality between opposing market outcomes.

---

## Core Mechanism

### 1. Which Pool Does Karma Price?
Each `Karma` oracle contract is associated with a specific Fate `PredictionPool`.
- The oracle reads `bullCoin`, `bearCoin`, and `baseToken` reserves directly from the pool.
- Submissions are evaluated against the participant's holdings in that specific market.
- **Pool Lifecycle & Oracle Immutability**: In Fate-Solidity, prediction pools have immutable oracles set at deployment (there is no `updateOracle` function). Karma seamlessly fits this architecture:
  - **New Pools**: A `Karma` oracle instance can be deployed first and passed as the oracle address when deploying a new Fate `PredictionPool`.
  - **Existing Pools**: A `Karma` oracle can be deployed for an existing pool, allowing subsequent pools, downstream derivative markets, or external protocols to consume prices.
  - **Shared Oracles**: Any contract can consume prices via standard `IOracle` (`readValue()`, `readValueInterval()`) or Chainlink-compatible `latestRoundData()` interfaces.

### 2. Neutrality Weighting
A participant holding only bull coins wants the oracle price to be higher. A participant holding only bear coins wants the price to be lower. Neither can be trusted.

However, a participant holding balanced positions has neutral marginal exposure: a price change does not enrich them at the expense of their other position. Their economic interest is solely in the accuracy and health of the market.

Under Fate's reserve redistribution mechanism:
$$dP_B / dp = 2 \cdot P_B \cdot q_S / p$$
$$-dP_S / dp = 2 \cdot P_S \cdot q_B / p$$

Dropping the symmetric factor $2/p$, the economically normalized exposures are:
$$\text{normalizedBull} = B \times P_B \times q_S$$
$$\text{normalizedBear} = S \times P_S \times q_B$$

Where:
- $B$: User's bull coin balance
- $S$: User's bear coin balance
- $P_B, P_S$: Current coin selling prices (`priceSell()`, scaled by `COIN_DENOMINATOR = 100_000`)
- $q_S = \text{bearReserve} / \text{totalReserve}$
- $q_B = \text{bullReserve} / \text{totalReserve}$

The participant's submission weight is:
$$\text{Weight} = \min(\text{normalizedBull}, \text{normalizedBear})$$

A one-sided holder has weight $0$. A balanced holder receives weight proportional to their balanced exposure.

### 3. Time-Decayed Weighted Average
Submissions are aggregated into two decaying accumulators:
$$\text{weightedPrice}(t) = \sum P_i \cdot W_i \cdot e^{-(t - t_i)/\tau}$$
$$\text{totalWeight}(t) = \sum W_i \cdot e^{-(t - t_i)/\tau}$$

$$\text{Price}(t) = \frac{\text{weightedPrice}(t)}{\text{totalWeight}(t)}$$

Because the time-decay factor $e^{-\Delta t / \tau}$ cancels out identically in the numerator and denominator ratio, read-time decay is unnecessary and decay is applied when folding in updates.

If no submissions exist or total weight decays to zero, `readValue()` returns `0`, matching the Fate oracle convention.

### 4. Non-Accumulating Resubmissions
If the same account resubmits a price, their prior contribution is decayed to the current timestamp and subtracted from the accumulators before the new submission is added. This prevents users from artificially multiplying their weight by repeatedly submitting.

---

## Security & Economic Guarantees

1. **Ownerless & Immutable Parameters**:
   - `Karma` contracts have no admin keys, no owner, and no privileged functions.
   - `pool`, `tau`, `minTotalBalance`, and `description` are all set at construction and immutable.
   - Because `minTotalBalance` cannot be modified after deployment, shared users of an oracle instance are fully protected from rug-pull parameter alterations.

2. **Sybil & Dust Spam Resistance**:
   - Balances are verified at submission time: a user's total balance (`bullCoin.balanceOf(user) + bearCoin.balanceOf(user)`) must meet or exceed `minTotalBalance` (default: 100 tokens).
   - Splitting capital across multiple wallets offers zero mathematical advantage due to the sub-additive/linear property of $\min(x, y)$, while sub-threshold wallets revert.

3. **Fee-Cost Trade-Off & Flash Loan Resistance**:
   - Acquiring balanced positions in the same transaction (e.g. via flash loans or immediate market buys) to skew the oracle price requires purchasing both bull and bear coins.
   - Fate charges protocol trading fees on both legs (~1.2% round-trip), plus any slippage incurred.
   - Because Karma aggregates prices via an exponential time-decay accumulator rather than taking an instantaneous spot snapshot, a single-block submission cannot permanently displace the historical time-weighted average without locking up capital over an extended duration.
   - The fee and slippage costs of entering and exiting the position reliably exceed any short-term profit extractable from manipulating the oracle price.

---

## Contract Architecture

```text
src/
├── Karma.sol               # Core oracle contract (IOracle, IKarmaOracle, Chainlink feeds)
├── KarmaAdapterFactory.sol # Factory deploying Karma per PredictionPool config
├── interfaces/
│   ├── IKarmaOracle.sol    # Karma oracle interface
│   └── IOracle.sol         # Standard Fate IOracle interface
└── lib/
    ├── PriceAverager.sol   # Time-decayed weighted averaging library
    ├── WadExp.sol          # Fixed-point exponential math (WAD)
    └── WeightLib.sol       # Neutrality weight computation
```

---

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)

### Build
```bash
forge build
```

### Test
```bash
forge test
```

### Deployment
To deploy using `KarmaAdapterFactory`:
```bash
forge script script/DeployKarma.s.sol --rpc-url <RPC_URL> --broadcast
```

`KarmaAdapterFactory` caches each `Karma` instance by `(pool, tau, minBalance)`. If an instance with the specified parameters already exists, the factory returns the existing address, enabling gas-efficient oracle sharing across protocols.

---

## License

See [LICENSE](LICENSE) (AEL).
