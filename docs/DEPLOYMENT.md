# Deployment — susu-contracts

> **Testnet only for the MVP.** Mainnet deployment is manual and requires explicit human
> approval. It is never automated and never happens from CI.

## Environments

| Environment | Chain | Purpose |
|---|---|---|
| `local` | Local Soroban sandbox / fixtures | Development |
| `testnet` | Stellar Testnet | Integration and beta |
| `production` | Stellar Mainnet | Controlled launch — **out of scope** |

Testnet and Mainnet must use separate deployer, admin, and treasury identities, plus
separate contract IDs, RPC URLs, and asset IDs. Never mix them.

## Identity model

| Role | Purpose | Notes |
|---|---|---|
| Deployer | Pays network fees for deployment | Never holds user funds |
| Protocol admin | Configures fee/treasury, pause new creation | Security-sensitive |
| Treasury | Receives the 0.50% fee | Dedicated; never a personal wallet |

Private keys never enter the frontend, the database, tracked source, or logs. Deployment
signing uses the Stellar CLI key store, not committed files.

## Testnet deployment

```bash
# 1. Create and fund a dedicated Testnet deployer.
stellar keys generate susu-deployer --network testnet --fund

# 2. Confirm the public address and record it.
stellar keys address susu-deployer

# 3. Build.
cargo build --workspace --target wasm32v1-none --release
# or: stellar contract build

# 4. Deploy the Group implementation (wasm hash is referenced by the Factory).
stellar contract upload \
  --wasm target/wasm32v1-none/release/susu_group.wasm \
  --source-account susu-deployer \
  --network testnet

# 5. Deploy the Factory.
stellar contract deploy \
  --wasm target/wasm32v1-none/release/susu_factory.wasm \
  --source-account susu-deployer \
  --network testnet

# 6. Initialize the Factory with admin, group wasm hash, treasury, and fee_bps.
#    (exact arguments finalize in Phase 2)

# 7. Verify IDs, then run the full Testnet acceptance checklist.
```

## Post-deployment verification

- [ ] Factory contract ID recorded and confirmed on the explorer.
- [ ] Group wasm hash matches the locally built artifact.
- [ ] `fee_bps` is exactly `50`.
- [ ] Treasury address is the dedicated treasury, not a personal wallet.
- [ ] Admin and deployer are separate identities.
- [ ] Testnet USDC SAC address verified against official Stellar documentation.
- [ ] Full end-to-end run passes: create, join, start, contribute, payout, complete.
- [ ] Treasury received exactly 0.50%; recipient received exactly 99.50%.
- [ ] Indexer ingests and reconciles the resulting events.

## Mainnet

Blocked. Requires the Mainnet readiness gate to be fully satisfied, an independent security
review to be completed with findings resolved or accepted, and explicit human approval.
See [`MAINNET_READINESS.md`](MAINNET_READINESS.md).
