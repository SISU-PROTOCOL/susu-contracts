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
