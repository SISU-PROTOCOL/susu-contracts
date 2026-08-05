# Contract Specification — susu-contracts

> Phase 0 draft. Signatures are fixed in Phase 1. Any change to semantics — especially
> fees, custody, authorization, payout selection, or round transitions — requires human
> review before implementation.

## Constants

| Name | Value | Notes |
|---|---|---|
| `FEE_BPS` | `50` | 0.50% protocol fee |
| `BPS_DENOMINATOR` | `10_000` | Basis-point denominator |
| Fee | `amount * FEE_BPS / BPS_DENOMINATOR` | Integer arithmetic only |
| Recipient amount | `amount - fee` | Integer arithmetic only |

Floating point is forbidden in any financial calculation.

## Status

`DRAFT → OPEN → ACTIVE → COMPLETED`

Round sub-state while `ACTIVE`:

`WAITING_FOR_CONTRIBUTIONS → READY_FOR_PAYOUT → PAYOUT_EXECUTED → NEXT_ROUND | COMPLETED`

Missing contribution means **WAIT**. There are no penalties in the MVP.

---

## Factory

### `initialize(admin, group_wasm_hash, treasury, fee_bps)`

Sets the admin authority, the wasm hash used to instantiate groups, the treasury address
that receives fees, and the fee in basis points.

- Must be callable only once.
- Must reject `fee_bps` above the accepted maximum.
- Must reject a zero/invalid treasury or admin.

### `create_group(...)`

Instantiates a new Group contract from `group_wasm_hash`, initializes it, and records it in
the registry.

- Must be blocked while paused.
- Must emit a structured creation event.

### `get_group(index_or_id)`

Returns the recorded address/metadata of a registered group.

### `get_group_count()`

Returns the number of groups created.

### `set_fee(admin, fee_bps)`

Updates the protocol fee. Admin-authorized. Must reject out-of-range values.

> Applies to groups created afterwards; existing groups' fee configuration must be
> handled explicitly and documented.

### `set_treasury(admin, treasury)`

Updates the treasury address. Admin-authorized.

### `pause(admin)` / `unpause(admin)`

Emergency control over **new group creation only**. Must never affect funds already held
by existing Group contracts.

---

## Group

### `initialize(...)`

Sets group configuration: members or member capacity, contribution amount, frequency,
member count, payout order, token, fee, and treasury. Configuration is mutable while
`DRAFT`, and **immutable once `ACTIVE`**.

### `join(member)`

Adds an authenticated member, subject to capacity and uniqueness rules.

### `start()`

Transitions `OPEN → ACTIVE` once configuration and membership requirements are satisfied.

### `contribute(member, amount, round)`

An authenticated member contributes the exact configured amount for the current round.

Must fail when: caller is not the member, member is not in the group, the round is not the
current round, the amount is not the exact configured amount, the token is not the
configured token, or the member has already contributed this round.

### `execute_payout()`

Permissionless once the current round is fully funded. Transfers `fee` to the treasury and
`recipient_amount` to the scheduled recipient, then advances the round exactly once.

Must fail when: the round is not fully funded (early payout), a payout has already been
executed for this round, or the group is not `ACTIVE`.

### Read functions

`get_group()`, `get_member(address)`, `get_round(round)`, `get_current_recipient()`,
`get_current_round()`, `get_pool_balance()`, `is_contribution_complete()`, `get_status()`.

---

## Invariants

1. `fee = amount * 50 / 10_000`
2. `recipient_amount = amount - fee`
3. `fee + recipient_amount == pool`
4. Exactly one contribution per member per round.
5. Exactly one payout per round.
6. Configured token only; exact configured amount only.
7. No early payout.
8. Recipient derives from the immutable payout order.
9. `payouts + fees <= valid contributions`
10. No arbitrary withdrawal, by any actor.
11. The final round completes exactly once.

## Storage & TTL

Every storage key and its TTL/archival behavior is documented in Phase 1, alongside the
tests that exercise archival and restoration. Instance storage is used for group
configuration and round state; persistent storage is used for per-member records.

## Events

Structured events are emitted for: creation, join, start, contribution, payout, fee, and
completion. Event shapes are designed as stable, idempotently indexable identities — the
indexer deduplicates on chain-derived event identity.
