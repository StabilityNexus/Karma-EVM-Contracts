<div align="center">
  <h1>Karma Protocol</h1>
  <p><strong>Self-sovereign, fully on-chain prediction-market price oracle</strong></p>
</div>

[![License: AEL](https://img.shields.io/badge/License-AEL-green.svg)](LICENSE)
[![Stability Nexus](https://img.shields.io/badge/Stability-Nexus-228B22?style=flat)](https://stability.nexus/)

---

## Overview

Traditional prediction markets and DeFi protocols depend on external oracles (e.g. Chainlink) to determine settlement prices. External oracles introduce third-party trust assumptions, delay risks, outage liabilities, and off-chain dependencies.

**Karma Protocol** is an on-chain, participant-driven price oracle. It reduces one-sided reporting influence with **economic neutrality weighting** based on opposing market positions.

---

## Core Mechanism

### 1. Which Pool Does Karma Price?
Each `Karma` oracle contract is constructed for one source prediction pool.
- The oracle reads `bullCoin`, `bearCoin`, and `baseToken` reserves directly from the pool.
- Submissions are weighted using the caller's Bull and Bear balances in that source pool.
- Other integrations can consume the price through Karma's oracle interfaces. Whether the source pool can also use it depends on that pool's oracle configuration.

### 2. Neutrality Weighting
A participant holding only bull coins wants the oracle price to be higher. A participant holding only bear coins wants the price to be lower. Neither can be trusted.

However, a participant holding balanced positions has neutral marginal exposure: a price change does not enrich them at the expense of their other position. Their economic interest is solely in the accuracy and health of the market.

Under the pool's reserve redistribution mechanism:
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
While the oracle is idle, `readValue()` returns the last computed average; `tau` changes relative weights when a later submission updates the average.

If no price has been submitted, `readValue()` returns `0`.

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

3. **Balance-at-submission trade-off**:
   - Karma reads Bull and Bear balances when `submitPrice` is called. Buying positions, submitting, and selling them in one transaction can leave a weighted contribution after the balances are gone.
   - Acquiring and exiting both positions may incur the source pool's fees and slippage. Karma does not lock reporter tokens, and these costs do not guarantee that manipulation is unprofitable.

---

## Contract Architecture

```text
src/
├── AccumulatorVault.sol     # dev role, receiver, and accumulated fee forwarding
├── Coin.sol                 # Bull/Bear ERC-20 market tokens
├── CoinFactory.sol          # Deploys the two coins for each pool
├── PredictionPool.sol       # Pool reserves, fee settings, and oracle rebalance
├── PredictionPoolFactory.sol# Creates pools and initializes their reserves
├── ChainlinkAdapterFactory.sol
├── Karma.sol                # Ownerless participant-weighted oracle
├── KarmaAdapterFactory.sol
├── interfaces/
│   ├── IAdapterFactory.sol
│   ├── IKarmaOracle.sol
│   ├── IOracle.sol
│   └── IAggregatorV3.sol
└── lib/
    ├── PriceAverager.sol
    ├── WadExp.sol
    └── WeightLib.sol
```

Pool creation uses an oracle that already exists. To use Karma for a pool, create the pool with an initial oracle, seed it with liquidity, create a Karma oracle using that pool as its source, submit an initial price, then have the pool owner call `updateOracle(karmaAddress)`. Karma can also serve a different pool or integration.

Each pool sets `devFee` at construction. `AccumulatorVault` sets `dev` and `devFeeReceiver` at deployment. Dev fees collect in the vault by token; `dev` calls `flushToken(token)` to send the balance to the current receiver. `dev` can change the receiver and transfer the dev role through proposal and acceptance.

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
See [dep.md](dep.md) for the full deployment sequence. The script deploys `AccumulatorVault`, `PredictionPoolFactory` (and its `CoinFactory`), `ChainlinkAdapterFactory`, and `KarmaAdapterFactory`:
```bash
forge script script/DeployKarma.s.sol:DeployKarma --rpc-url <RPC_URL> --broadcast
```

`KarmaAdapterFactory` caches each Karma instance by `(pool, tau, minBalance)`. Pool factories do not register oracles; they only check that the supplied oracle implements `readValue()`.

---

## License

See [LICENSE](LICENSE) (AEL).
