# Architecture — susu-contracts

> Phase 1. This document is kept in sync with the implementation and is not a substitute
> for reading the code.

## Role

`susu-contracts` holds the **only** financial authority in the Susu Protocol. Nothing
off-chain may decide balances, payout recipients, eligibility, or authorization.

## Topology

**Factory + one Group contract per group.** This is a deliberate choice: each group's pool
lives in its own contract instance, so a defect or compromise in one group's state cannot
reach another group's funds.

```text
                    ┌──────────────────────────┐
   admin ──────────▶│      Factory             │
                    │  - registry of groups    │
                    │  - group wasm hash       │
                    │  - treasury + fee_bps    │
                    │  - pause new creation    │
                    │  NEVER holds funds       │
                    └───────────┬──────────────┘
                                │ create_group(...)
                                ▼
                    ┌──────────────────────────┐
   members ────────▶│      Group  N            │
                    │  - members + payout order│
                    │  - round state           │
                    │  - pool balance          │
                    │  FINANCIAL AUTHORITY     │
                    └───────┬──────────┬───────┘
                            │          │
                99.50%      ▼          ▼      0.50%
                    scheduled       treasury
                    recipient
```

## Why a Factory

- One canonical registry of groups, so clients can resolve a group from a single contract.
- Group logic is deployed once as a wasm hash and instantiated per group, keeping
  per-group storage isolated.
- New-group creation can be paused in an emergency without touching existing groups'
  funds — the Factory has no ability to move them.

## Why per-group contracts

- Storage and authorization are naturally partitioned per group.
- A group's financial configuration is immutable after start, so members can verify the
  rules they joined under.
- Total-loss blast radius is limited to a single group.

## Authority summary

| Actor | Can do | Cannot do |
|---|---|---|
| Factory admin | Configure fee/treasury, pause new group creation | Move any group's funds |
| Group creator | Create the group; its configuration is fixed at construction | Withdraw funds, change any rule after construction |
| Member | Join, contribute, and trigger a valid payout | Contribute twice, contribute the wrong amount, force early payout |
| Anyone | Execute a payout once a round is fully funded and valid | Skip contract checks, choose the recipient |
| Treasury | Receive the 0.50% fee | Withdraw group funds |
| Backend / indexer | Read, index, reconcile | Any financial authority |

## Related documents

- [`CONTRACT_SPEC.md`](CONTRACT_SPEC.md) — full interface and storage layout.
- [`THREAT_MODEL.md`](THREAT_MODEL.md) — adversaries and mitigations.
- [`../SECURITY.md`](../SECURITY.md) — invariants and disclosure policy.
