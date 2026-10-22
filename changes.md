# Changes

| Area | Change | Result |
|---|---|---|
| Pool deployment | Added `PredictionPoolFactory`, `PredictionPool`, `CoinFactory`, and paired `Coin` tokens. | Karma's frontend can create and seed markets without importing Fate pool contracts. |
| Oracle selection | Pool creation accepts an `IOracle` that responds to `readValue()`; no `registerOracle` call or registry exists. The frontend creates adapters before calling `createPool`. | Factory creation works with direct Chainlink or Karma adapters. |
| Pool pricing | Added reserve rebalancing from the configured oracle price and permissioned `updateOracle`. | A seeded pool can start on Chainlink and later use Karma after a reporter submits a price. |
| Fees | Pool and coin constructors store `devFee`; fees use denominator `100,000`. Dev fees accrue in `AccumulatorVault`. | Pool fee rates are fixed at creation and accrued tokens can be flushed to the receiver. |
| Dev controls | `AccumulatorVault` constructor sets `dev` and `devFeeReceiver`; dev can update the receiver and propose a two-step dev transfer. | The supplied full address receives fees after the dev flushes each token. |
| Chainlink adapter | Added a feed adapter and factory with per-feed caching; removed the unnecessary pool-factory dependency. | Chainlink can initialize pools without a registry call. |
| Karma oracle | Kept the ownerless oracle and normalized cache behavior. | Oracle settings remain immutable and factory defaults share one instance. |
| Review fixes | Kept plain `min(normalizedBull, normalizedBear)`, denomination scaling, replacement of prior submissions, zero empty read, and no read-time decay. | Submission weight preserves exposure size and repeated submissions do not compound a user's weight. |
| Frontend | Fee fields and quote estimates use `devFee`; removed unused `createPoolWithAdapter` and Chainlink factory pool-factory ABI entries. | Frontend calls match the Karma contracts and adapter-first pool creation flow. |
| Build | Enabled IR compilation for the multi-argument pool factory interface. | `forge build` compiles with the checked-in Solidity 0.8.23 configuration. |
