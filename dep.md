# Karma deployment guide

This deploys the Karma pool system and oracle adapters. Deployments are not broadcast until you run the command in step 4.

## 1. Build and check

Open PowerShell in `Karma-EVM-Contracts`:

```powershell
forge build
forge test
```

Foundry is configured for Solidity 0.8.23 with IR compilation to compile the pool factory's existing multi-argument interface.

## 2. Configure deployment values

Copy `.env.example` to `.env`, then set:

| Variable | Use |
|---|---|
| `RPC_URL` | Target network RPC endpoint. Keep the Alchemy URL in the ignored `.env` file. |
| `PRIVATE_KEY` | Deployer key as a `0x`-prefixed hex string; do not commit it. |
| `DEV_ADDRESS` | Initial fee-vault dev. |
| `DEV_FEE_RECEIVER` | Initial address that receives flushed dev fees. |
| `PREDICTION_POOL` | Optional existing pool on the chain selected by `RPC_URL`; the script checks that it is an initialized pool on that chain before broadcasting. |
| `TAU` | Optional Karma decay constant; default `124651`. |
| `MIN_BALANCE` | Optional Karma submission threshold; default `100e18`. |
| `DESCRIPTION` | Optional Karma oracle description. |

The treasury address belongs in `DEV_FEE_RECEIVER`. `DEV_ADDRESS` is the administrator who can flush fees, change the receiver, and propose a dev-role transfer. They may be the same wallet.

Set `RPC_URL` in `.env` to the endpoint for the target chain. For the current Base Mainnet setup, the Alchemy URL is stored there. Load it into the current PowerShell session without printing it:

```powershell
$rpcUrlLine = Get-Content .env | Where-Object { $_ -match '^RPC_URL=' } | Select-Object -First 1
$env:RPC_URL = $rpcUrlLine.Substring('RPC_URL='.Length)
```

Foundry reads `.env` for script variables. PowerShell commands such as `cast` do not; set `$env:PRIVATE_KEY` and other values in the session before using those commands.

## 3. Simulate

```powershell
forge script script/DeployKarma.s.sol:DeployKarma --rpc-url $env:RPC_URL
```

The script first checks that a non-empty `PREDICTION_POOL` address resolves to an initialized pool and deployed token contracts on the chain selected by `RPC_URL`. It then deploys, in order, `AccumulatorVault`, `PredictionPoolFactory` (which deploys its `CoinFactory`), `ChainlinkAdapterFactory`, and `KarmaAdapterFactory`. It prints each address. It also creates a Karma oracle only if `PREDICTION_POOL` is set.

## 4. Broadcast and verify

After confirming the network, deployer, dev, and complete receiver addresses:

```powershell
forge script script/DeployKarma.s.sol:DeployKarma `
  --rpc-url $env:RPC_URL `
  --broadcast
```

For explorer verification, configure the target chain and API key in Foundry and add `--verify`. Save all deployed addresses, transaction hashes, and constructor settings.

## 5. Create an initial pool

Create a Chainlink adapter for the network's feed by calling `ChainlinkAdapterFactory.createAdapter(feedAddress)`. Then approve the base token to `PredictionPoolFactory` and call `createPool` with:

`name, baseToken, oracle, bullName, bullSymbol, bearName, bearSymbol, mintFee, burnFee, creatorFee, devFee, initialDeposit`.

Fees use a `100,000` denominator (`300` means `0.3%`). Pool fee rates are fixed when that pool is created. The initial deposit is split between the Bull and Bear reserves; seed the pool if you intend to use it as Karma's source.

## 6. Create and activate Karma

After the pool exists, call `KarmaAdapterFactory.createKarma(pool, tau, minBalance, description)`. There is no `registerOracle` step. An eligible reporter must hold both pool coins, meet `minBalance`, and call `submitPrice(price)`. `readValue()` returns `0` before the first valid submission.

Once Karma has a price, the pool owner can call `PredictionPool.updateOracle(karmaAddress)`. The source pool Karma reads and the pool consuming Karma's price may be different.

## 7. Manage dev fees

Dev fees are transferred from each coin into `AccumulatorVault`. The current dev flushes a token's full accumulated balance:

```powershell
cast send $env:VAULT_ADDRESS "flushToken(address)" $env:TOKEN_ADDRESS `
  --rpc-url $env:RPC_URL --private-key $env:PRIVATE_KEY
```

The current dev may change the receiver with `setDevFeeReceiver(address)`. To transfer the dev role, the current dev calls `proposeDevTransfer(newDev)`; `newDev` then calls `acceptDevTransfer()`.

## 8. Configure the frontend

Set the target chain's `KarmaPoolFactories`, `ChainlinkAdapterFactories`, and `KarmaAdapterFactories` in `Karma-EVM-Frontend/src/utils/addresses.ts`. Confirm the addresses against the deployment record before publishing the frontend.
