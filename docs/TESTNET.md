# Testnet — susu-contracts

Testnet is the MVP integration environment. Everything is public and worthless there, which
makes it the right place to prove the mechanism before anyone risks real funds.

## Network details

| Setting | Value |
|---|---|
| Network | Stellar Testnet |
| RPC | `https://soroban-testnet.stellar.org` |
| Passphrase | `Test SDF Network ; September 2015` |
| USDC SAC | `CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA` |
| USDC issuer | `GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5` |

Verify these against official Stellar documentation before relying on them. Never mix
Testnet and Mainnet asset IDs.

## Current Testnet deployment

Deployed by `scripts/deploy-testnet.sh`. All addresses below are public; private keys
live only in the Stellar CLI key store and are never committed.

| Item | Value |
|---|---|
| Factory contract | `CCC7KAX4V4GJD6FVG6GSYQ4I2D2B3CWEOQMIX6YM4QBGXTA6INCGRUYC` |
| Group wasm hash | `16fee744280d90d385faa3a36d0ec37247423ca372986a019dc16db5da1fbd63` |
| Factory admin | `GBDCB4HSYZZEOYD3W36GYLRRUQKRW3JLNXGQXTNJD7MWQNWYPMIE6TXS` |
| Treasury | `GBG4MSIEUTONQSE7SSUQ6QZTQPNMKCSESZ6TZKZCMZRMAKZSDO6QPCYK` |
| Deployer | `GBPJ3JJLZ7XPV6CGF3ABPSTXAATKRBCU2L6P66LHCGLYPBVMJX5BEFH6` |
| `fee_bps` | `50` |

The Factory is deployed with its `__constructor`, so it is never observable in an
uninitialized state; `get_config` was read back from the chain after deployment and
confirms the admin, treasury, wasm hash, `fee_bps = 50`, and `group_count = 0`.

### Test asset, not Testnet USDC

The automated E2E runs against a **test asset** (`TSTUSD`), deployed as a Soroban Asset
Contract at `CDK6IB7PR3HFNOLH4R37ODLVTNYCVT2NX4SIBWKQXLKJNHJJU3PEWGA7`.

This is deliberate. Circle's Testnet USDC issuer is the only account that can mint
Testnet USDC, so it cannot be obtained programmatically; the faucet is a manual web flow.
The contracts are token-agnostic by design (the token is a `create_group` parameter), so
a test asset exercises the identical code path. The product remains **USDC-only**:
production groups are created with the USDC SAC above.

To run the same scenario against Testnet USDC, fund the three member accounts from
Circle's faucet and set `TOKEN_SAC` to the USDC SAC — the lifecycle and assertions are
unchanged.

### Verified on-chain

The canonical reference scenario (**3 members × 10 USD**) has been executed end-to-end
against Testnet and passed, with balances asserted directly from chain state:

| Quantity | Expected | Observed |
|---|---|---|
| Each member net change | −0.15 USD | `-1500000` stroops |
| Treasury net change | +0.45 USD (3 × 0.15) | `4500000` stroops |
| Group balance after completion | 0 | `0` |
| Final status | `Completed` | `Completed` |

Each member paid 30 USD and received one 29.85 USD payout, so each member's cost is
exactly the 0.50% fee. Reproduce with:

```bash
./scripts/deploy-testnet.sh   # idempotent; reuse the existing deployment
./scripts/e2e-testnet.sh      # idempotent; safe to re-run
```

## Identities

Testnet uses three separate identities, each created and funded independently:

- `susu-deployer` — deployment and network fees
- protocol admin — configuration authority
- treasury — dedicated fee recipient, never a personal wallet

```bash
stellar keys generate susu-deployer --network testnet --fund
stellar keys address susu-deployer
```

## Acceptance checklist

The Testnet beta is not complete until every item passes with evidence.

### Auth and account

- [ ] Signup, email verification, and login.
- [ ] Forgot password, reset password, change password.
- [ ] Wallet connect and wallet linking via nonce → signature → verification.

### Profile

- [ ] Profile edit.
- [ ] Avatar upload and removal with correct access control.

### Lifecycle

- [ ] Create group.
- [ ] Invite a member and join via invite code.
- [ ] Start the group.

### Financial correctness

- [ ] Valid contribution succeeds.
- [ ] Invalid contribution rejected: wrong amount, wrong token, wrong member, wrong round.
- [ ] Duplicate contribution rejected.
- [ ] Early payout rejected.
- [ ] Valid payout succeeds.
- [ ] Treasury receives exactly 0.50%.
- [ ] Recipient receives exactly 99.50%.
- [ ] Duplicate payout rejected.
- [ ] Every member receives exactly one payout across all rounds.
- [ ] Final round completes exactly once.

### Indexing and resilience

- [ ] Indexer records all events and the database matches chain state.
- [ ] Full indexer rebuild from history reproduces the same state.
- [ ] Reconciliation detects and repairs an artificially introduced divergence.
- [ ] RPC failure and retry behavior verified.
- [ ] Duplicate request behavior verified.

## Reference scenario

The canonical end-to-end check is **3 members × 10 USDC = 30 USDC**:

| Quantity | Value |
|---|---|
| Pool | 30 USDC |
| Fee (0.50%) | 0.15 USDC |
| Recipient | 29.85 USDC |

Repeated across all rounds, with an assertion that each member receives exactly one payout.
