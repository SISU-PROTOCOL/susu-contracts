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

Deployment is scripted and idempotent. Private keys stay in the Stellar CLI key store;
only public addresses are written out.

```bash
# One command: ensures identities, builds, uploads the Group wasm, deploys the
# Factory with its __constructor, verifies the config on-chain, and writes
# .env.testnet (gitignored, public addresses only).
./scripts/deploy-testnet.sh

# Then drive the full lifecycle and assert the resulting balances.
./scripts/e2e-testnet.sh
```

`deploy-testnet.sh` creates and funds three distinct identities — deployer, admin and
treasury — and refuses to proceed if any two collide. The Factory is constructed at
deploy time, so it is never observable in an uninitialized state and its admin cannot be
front-run.

The group implementation is uploaded once; the Factory stores its wasm hash and
instantiates groups from it via `deploy_v2` under a deterministic, monotonic salt.

Override the defaults with environment variables: `SUSU_DEPLOYER_IDENTITY`,
`SUSU_ADMIN_IDENTITY`, `SUSU_TREASURY_IDENTITY`, `PROTOCOL_FEE_BPS`.

> Testnet only. The script refuses to run against any other network.

## Post-deployment verification

`deploy-testnet.sh` performs the on-chain checks itself and fails the deployment if any
of them regress, so they are enforced rather than left to a manual pass:

- [x] Factory contract ID recorded and confirmed on the explorer.
- [x] Group wasm hash matches the locally built artifact (read back from `get_config`).
- [x] `fee_bps` is exactly `50`.
- [x] Admin and deployer are separate identities (the script refuses collisions).
- [x] Full end-to-end run passes: create, join, start, contribute, payout, complete.
- [x] Treasury received exactly 0.50%; recipient received exactly 99.50%.
- [x] Every member receives exactly one payout; the group retains nothing.
- [x] Final round completes exactly once (`Completed`).
- [x] Every expected refusal is refused with the right contract error, asserted
      against the deployed contracts rather than only in unit tests: create with a
      single member, a zero contribution, or a zero frequency; start before capacity;
      join twice, join when full, join after starting; contribute while `Open`, the
      wrong amount, the wrong round, as a non-member, twice in a round, to a completed
      group; and payout before the round is funded and after completion.

      These refusals are asserted by simulation only, so the checks cannot move funds
      and cannot be satisfied by a transaction that silently changed state.

      Testnet's RPC fails intermittently, so a failing call is classified before it is
      interpreted. A contract refusal is recognised by its `Error(Contract, #N)`, and
      anything else is treated as the network having returned no verdict and is retried.
      The classification is by exclusion rather than by a list of transport messages,
      because those messages are unbounded — each outage so far has produced a new one,
      and an unrecognised one used to surface as "refused, but not with #13", which
      points at the contract for a failure that never reached it.

      The script also hashes itself at startup and re-checks on exit. Bash reads scripts
      lazily by byte offset, so editing one mid-run makes it execute misaligned content;
      a mismatch fails the run rather than reporting an outcome that cannot be trusted.

Still outstanding before the beta:

- [ ] Testnet USDC SAC address re-verified against official Stellar documentation, and the
      canonical scenario executed against real USDC (the automated run uses a test asset —
      see [`TESTNET.md`](TESTNET.md#test-asset-not-testnet-usdc)).
- [ ] Indexer ingests and reconciles the resulting events.

## Mainnet

Blocked. Requires the Mainnet readiness gate to be fully satisfied, an independent security
review to be completed with findings resolved or accepted, and explicit human approval.
See [`MAINNET_READINESS.md`](MAINNET_READINESS.md).
