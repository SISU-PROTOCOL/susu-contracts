# Susu Protocol — Contracts

[![CI](https://github.com/Susu-Protocol/susu-contracts/actions/workflows/ci.yml/badge.svg)](https://github.com/Susu-Protocol/susu-contracts/actions/workflows/ci.yml)

Soroban (Rust/Wasm) smart contracts for **Susu Protocol** — a non-custodial rotating
savings protocol on Stellar.

> **Status: Phase 0 — scaffolding.** The Factory and Group interfaces are implemented
> in Phase 1. Nothing here is audited, and no contract has been deployed to Mainnet.

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
stellar contract build     # or: cargo build --target wasm32v1-none --release --workspace
cargo deny check
cargo audit
```

## Security

Contracts are unaudited. See [`SECURITY.md`](SECURITY.md) for the disclosure process.
Changes affecting financial invariants, custody, authorization, payout behavior, or fees
require human review before merge.

## License

[MIT](LICENSE)
