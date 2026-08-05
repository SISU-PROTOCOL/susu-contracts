# Mainnet Readiness — susu-contracts

> **Status: BLOCKED — not started.**
>
> Mainnet deployment is manual and requires explicit human approval. It must never be
> automated, and it must not happen until every gate below is satisfied with evidence.

## Gate

All items must be complete. Any unchecked item blocks Mainnet.

### Contracts

- [ ] Contract interface frozen.
- [ ] Full test suite passes, including every negative path.
- [ ] All eleven financial invariants explicitly tested.
- [ ] Boundary and invalid-configuration cases covered.
- [ ] Final round completes exactly once — proven by test.
- [ ] Storage keys and TTL/archival behavior documented and tested.
- [ ] Property/invariant tests in place.
- [ ] No arbitrary withdrawal path exists anywhere in the code.
- [ ] Upgrade strategy reviewed and documented; no silent upgrades.

### Security

- [ ] Threat model reviewed against the final implementation.
- [ ] Independent security review / audit completed.
- [ ] All findings resolved or explicitly accepted with rationale.
- [ ] Dependency audit clean (`cargo audit`, `cargo deny`).
- [ ] Secret scanning clean across history.

### Operations

- [ ] Admin and treasury controls implemented and documented.
- [ ] Production admin/treasury use appropriate key management or multisig.
- [ ] Separate Mainnet identities from Testnet.
- [ ] Monitoring and alerting in place.
- [ ] Incident and recovery runbook tested.

### Configuration

- [ ] Current Mainnet USDC asset IDs verified against official Stellar documentation.
- [ ] Fee confirmed at exactly 50 bps.
- [ ] Treasury confirmed as a dedicated address, not a personal wallet.
- [ ] Mainnet configuration reviewed independently from Testnet config.

### Process

- [ ] Legal / compliance review for intended model and jurisdictions.
- [ ] Explicit human approval recorded.
- [ ] Manual, supervised deployment.

## Explicit statements

- This software **has not been audited**.
- No claim of being secure, audited, or production-ready is made or implied.
- Mainnet deployment will not be performed by CI or by an autonomous agent.

## Remaining unknowns

- Formal verification of fee and payout arithmetic is not planned.
- Upgrade authority design is not finalized.
- Compliance posture for target jurisdictions is not assessed.
