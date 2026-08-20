# Threat Model — susu-contracts

> Phase 1 — updated against the implemented contracts. This document does not
> claim the system is secure — it records what we are defending against and how.

## Assets

1. **Member contributions** — USDC held by Group contracts between contribution and payout.
2. **Payout integrity** — the correct recipient receives the correct amount, exactly once.
3. **Fee integrity** — exactly 0.50% reaches the treasury, never more.
4. **Round state** — one contribution per member per round, one payout per round.
5. **Admin authority** — limited to protocol configuration; never custody.
6. **Deployer key** — pays network fees only.

## Trust boundaries

- **On-chain contracts** are trusted to enforce all financial rules.
- **Everything off-chain** (frontend, backend, indexer, database) is untrusted with respect
  to financial authority and may be compromised without moving funds.
- **Wallet keys** are held by users, never by the protocol.

## Adversaries and mitigations

### Malicious creator or member

*A creator tries to withdraw the pool or redirect a payout; a member tries to contribute
twice, underpay, or claim a payout early.*

- No arbitrary withdrawal exists — there is no code path for it.
- Financial configuration is immutable after `start()`.
- The recipient is derived from the payout order, never supplied by the caller.
- Round/member guards prevent duplicate contribution and duplicate payout.
- Exact-amount and configured-token checks reject malformed contributions.

### Frontend compromise

*An attacker injects a transaction that sends funds elsewhere.*

- The frontend has no custody and no authority; it can only propose transactions.
- All transfers are constrained by contract logic to the configured token, amount, and
  recipient derived from the payout order.
- Users see transaction details and simulate before signing.

### Backend or indexer compromise

*An attacker alters the database to misrepresent balances or recipients.*

- The backend and indexer hold no keys and cannot sign or authorize anything.
- Chain state is authoritative; the database is a rebuildable cache.
- Reconciliation detects and repairs divergence.

### Admin or treasury compromise

*The admin key or treasury address is stolen.*

- Admin authority is limited to fee/treasury configuration and pausing new group creation.
- Admin cannot withdraw funds from any group; the treasury can only receive fees.
- Roles are separate accounts, and production use should apply multisig/key management.
- Pausing new creation limits ongoing damage without touching existing pools.

### Wrong token, amount, or recipient

- The contract validates the token against configuration and the amount against the exact
  configured value.
- The recipient is computed from the immutable payout order, so it cannot be substituted.

### Duplicate and replay

- On-chain round/member contribution guards and one-payout-per-round guards are the
  authoritative defense.
- Indexing is idempotent on chain-derived event identity.

### RPC or database failure

- Failures delay visibility, not settlement. Retries plus chain verification are used.
- The database can always be rebuilt from chain history.

### Storage, TTL, and upgrade abuse

- Every storage key and its TTL/archival behavior is documented in
  [`CONTRACT_SPEC.md`](CONTRACT_SPEC.md#storage--ttl).
- TTL extension is exercised by a test (`ttl_is_extended_by_an_interaction`).
  Archival and restoration paths are not yet exercised end-to-end.
- Neither contract has an upgrade entry point: there is no `upgrade`, `set_wasm`, or
  admin-controlled code replacement. Upgrade authority is therefore nil by
  construction, and any change ships as a new deployment.
- Financial upgrades require human security review.

### Denial of service and transaction substitution

- Payout execution is permissionless, so a single stalled actor cannot block a valid
  payout indefinitely.
- Transaction details are simulated and displayed before signing to reduce substitution
  and phishing risk.

## Explicit non-goals

Susu Protocol does not implement a protocol token, governance, lending, borrowing, yield,
staking, fiat settlement, multi-chain bridging, collateral, penalties, reputation, or
insurance. Threats arising from those systems are out of scope by design.

## Open items

- Formal verification of the fee and payout arithmetic is not yet performed.
- Storage archival and restoration paths (as opposed to TTL extension) are not yet
  exercised end-to-end.
- Independent security review is Phase 11 and has not happened yet.
