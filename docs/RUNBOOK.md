# Runbook — susu-contracts

Operational procedures for Susu Protocol contracts. Contracts are deployed to Testnet only
for the MVP.

## Core principle

**Chain state is authoritative.** Contracts hold and move funds without depending on the
backend, the indexer, the database, or the frontend. Any of those can fail without
affecting settlement.

## Incident procedures

### Frontend is down

- **Impact:** Users cannot submit transactions. Funds are unaffected.
- **Action:** Restore or redeploy the web app. Contract funds remain governed by contract
  logic throughout.

### API is down

- **Impact:** Convenience features and read APIs are unavailable. On-chain authority is
  unaffected.
- **Action:** Restore the API. Users can still interact with contracts directly.

### Indexer is down or checkpoint is stale

- **Impact:** The database lags chain state. No financial impact.
- **Action:** Restart from the persisted checkpoint and reconcile. See
  [the recovery procedure](#indexer-recovery).

### Database corruption

- **Impact:** Read models are wrong or unavailable. No financial impact.
- **Action:** Restore from backup, or rebuild entirely from chain history. The chain is the
  source of truth.

### Transaction pending or stuck

- **Action:** Inspect the chain before retrying. Never blindly resubmit — confirm whether
  the transaction landed first to avoid duplicate submission.

### Payout discrepancy reported

- **Action:** Inspect the transaction, its events, and contract state before touching the
  database. Assume the chain is correct and the database or UI is wrong until proven
  otherwise. Never "fix" a discrepancy by editing balances.

### Admin key suspected compromised

- **Action:** Follow the security process in `SECURITY.md`. If available, pause new group
  creation to limit further exposure. Existing groups' funds cannot be withdrawn by the
  admin, so they remain governed by contract logic.

### Contract bug discovered

- **Action:** Stop new group creation if possible, then activate the security process.
  Do not attempt an ad-hoc fix on a live contract. Financial changes require human review.

## Indexer recovery

1. Identify the last persisted checkpoint (last processed ledger).
2. Confirm the contract/RPC is reachable and note the current ledger.
3. Restart the scheduled index function; it resumes from the checkpoint.
4. Verify idempotent upserts did not duplicate events (event identity is unique).
5. Run reconciliation against contract state.
6. If state is irrecoverably wrong, perform a full rebuild from the deployment ledger.

## Deployment rollback

Soroban contracts are immutable once deployed. There is no rollback of a deployed contract.
Recovery options are limited to pausing new group creation and deploying a corrected
implementation for future groups — existing groups continue under their original rules.
This is a deliberate trade-off in favor of predictable member expectations.

## Escalation

Any change to fee semantics, custody, authorization, payout behavior, or upgrade authority
requires human approval before implementation.
