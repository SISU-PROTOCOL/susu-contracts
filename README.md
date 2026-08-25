# Susu Protocol — Contracts

[![CI](https://github.com/SISU-PROTOCOL/susu-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/SISU-PROTOCOL/susu-contracts/actions/workflows/ci.yml)

Soroban (Rust/Wasm) smart contracts for **Susu Protocol** — a non-custodial rotating
savings protocol on Stellar.

> **Status: Phase 2 — deployed to Stellar Testnet.** The Factory and Group contracts,
> their full test suites, and the Factory→Group deployment integration test are in place
> and green in CI. The Factory is deployed and verified on Testnet, and the canonical
> 3 × 10 USD lifecycle passes on-chain with balances asserted from chain state (see
> [`docs/TESTNET.md`](docs/TESTNET.md)). Nothing here is audited, and no contract has
> been deployed to Mainnet. See [`docs/CONTRACT_SPEC.md`](docs/CONTRACT_SPEC.md) for the
> implemented interface.

## What Susu is

Members of a group contribute a fixed amount at a fixed interval. Once every member has
contributed for the current round, the pool is paid to the scheduled recipient, minus a
transparent **0.50% (50 bps)** protocol fee sent to a dedicated treasury. Rounds continue
until every member has received exactly one payout.

## Architecture

**Factory + one Group contract per group.** The Factory creates and registers groups and
never holds funds. Each Group contract is the sole financial authority for its own pool.

```text
Factory ──creates──> Group N   ──> 99.50% scheduled recipient
                              └──>  0.50% treasury
```

## Financial invariants

```text
fee              = amount * fee_bps / 10_000      (integer arithmetic only)
recipient_amount = amount - fee
fee_bps          = 50
fee + recipient_amount == pool
```

- One contribution per member per round.
- One payout per round; no early payout.
- Configured token only, exact configured amount.
- Recipient is derived from the immutable payout order.
- No arbitrary withdrawal — not by creator, admin, backend, or treasury.
- Final round completes exactly once.

**Floating point is never used for money.**

## Layout

```text
contracts/
  factory/   # creates + registers groups; never custodies funds
  group/     # per-group pool; the financial authority
docs/        # contract spec, threat model, deployment + runbook
```

## Development

Prerequisites: Rust ≥ 1.84 (pinned in `rust-toolchain.toml`) with the `wasm32v1-none`
target, and the Stellar CLI.

```bash
rustup target add wasm32v1-none

cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-contracts.sh   # or: stellar contract build
cargo test -p susu-factory --features wasm-integration
cargo deny check
cargo audit
```

### Testnet

Deployment scripts for Stellar Testnet. Both are idempotent; see
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) and [`docs/TESTNET.md`](docs/TESTNET.md).

```bash
./scripts/deploy-testnet.sh   # build, upload, deploy the Factory, verify on-chain
./scripts/e2e-testnet.sh      # full 3x10 lifecycle, plus the refusals, with balance assertions
```

The E2E script retries transport failures (Testnet's RPC is intermittently flaky),
and distinguishes them from contract refusals so a network blip is never reported as
a contract bug. Both scripts hash themselves at startup and re-check on exit, and
refuse to trust a run if they were modified while it was in flight — bash reads
scripts by byte offset, so a mid-run edit would otherwise execute misaligned content.

The deployed Factory is recorded in [`docs/TESTNET.md`](docs/TESTNET.md).

## Security

Contracts are unaudited. See [`SECURITY.md`](SECURITY.md) for the disclosure process.
Changes affecting financial invariants, custody, authorization, payout behavior, or fees
require human review before merge.

## License

[MIT](LICENSE)
