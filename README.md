# hello-data-service

A minimal working [Horizon](https://thegraph.com/docs/horizon) data service built as a companion to the guide [How to Build and Deploy a Data Service on The Graph's Horizon Framework](https://www.lodestar-dashboard.com/blog/how-to-build-a-horizon-data-service).

Use it as a starting point or a reference when building your own service.

## What's in here

| File | Purpose |
|---|---|
| `src/HelloDataService.sol` | The data service contract — ~120 lines, full provider lifecycle, `collect()`, no slashing |
| `script/Deploy.s.sol` | Foundry deploy script — spins up the full Horizon stack locally (mock staking, real payment contracts) and runs the complete setup sequence |
| `remappings.txt` | Working remappings for the `graphprotocol/contracts` package |
| `foundry.toml` | Project config — includes `via_ir = true` (required to avoid stack-too-deep in deploy scripts) |

## Prerequisites

- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash && foundryup`

## Setup

Clone and install dependencies:

```bash
git clone https://github.com/cargopete/hello-data-service
cd hello-data-service
forge install graphprotocol/contracts
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install foundry-rs/forge-std
```

Compile:

```bash
forge build
```

## Run locally

Start Anvil:

```bash
anvil --chain-id 412346 --block-time 1 --accounts 10
```

Deploy the full stack (Horizon contracts + HelloDataService + provider registration + escrow funding):

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --skip-simulation
```

The script deploys in four phases:
1. Horizon stack — GRT token, controller, mock staking, GraphPayments, PaymentsEscrow, GraphTallyCollector
2. HelloDataService
3. Provider provisions stake and registers
4. Gateway authorises its signing key and funds the escrow bucket

On success you'll see the deployed addresses and confirmation that the provider is registered and escrow is funded.

## Verify the lifecycle

```bash
SERVICE=<address from deploy output>
PROVIDER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
PROVIDER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
RPC=http://127.0.0.1:8545

# Check registration
cast call $SERVICE "registeredProviders(address)(bool)" $PROVIDER --rpc-url $RPC

# Deregister
cast send $SERVICE "deregister(address,bytes)" $PROVIDER "0x" \
  --rpc-url $RPC --private-key $PROVIDER_KEY

# Re-register
DATA=$(cast abi-encode "f(string,address)" "Hello again!" "0x0000000000000000000000000000000000000000")
cast send $SERVICE "register(address,bytes)" $PROVIDER $DATA \
  --rpc-url $RPC --private-key $PROVIDER_KEY
```

## Contract overview

`HelloDataService` inherits the three base contracts the guide recommends:

```solidity
contract HelloDataService is Ownable, DataService, DataServiceFees, DataServicePausable
```

- **`DataService`** — `GraphDirectory` (upgrade-safe contract resolution), provision validation, `onlyAuthorizedForProvision`
- **`DataServiceFees`** — `_lockStake()` / `_releaseStake()` for the dispute window
- **`DataServicePausable`** — emergency stop

Provider registration accepts a greeting string and an optional `paymentsDestination` address (hot operator key → cold storage wallet pattern). Slashing reverts loudly — correct behaviour for any service whose outputs aren't verifiable on-chain.

## Key things the guide taught us (the hard way)

- Import `IGraphTallyCollector` and `IGraphPayments` from `@graphprotocol/horizon/interfaces/`, not `@graphprotocol/horizon/payments/`
- `@openzeppelin/contracts-upgradeable/` and `@graphprotocol/horizon/mocks/` both need explicit remapping entries — a single wildcard won't cover them
- `deregister` is not in `IDataService` — don't mark it `override`
- `via_ir = true` in `foundry.toml` is required for deploy scripts that instantiate several contracts in one function

## Further reading

- [Guide: How to Build a Horizon Data Service](https://www.lodestar-dashboard.com/blog/how-to-build-a-horizon-data-service)
- [Dispatch](https://github.com/cargopete/dispatch) — production JSON-RPC data service this guide is drawn from
- [SubgraphService](https://github.com/graphprotocol/contracts/tree/main/packages/subgraph-service) — reference implementation from The Graph core team
- [SubstreamsDataService](https://github.com/graphprotocol/substreams-data-service) — sidecar/session model reference
- [GIP-0066: Horizon](https://forum.thegraph.com/t/gip-0066-introducing-graph-horizon-a-data-services-protocol/5989)

## License

Apache-2.0
