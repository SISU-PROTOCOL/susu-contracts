# Security Policy

## Status

Susu Protocol contracts are **in active development and have not been audited**. They are
deployed to Stellar **Testnet only**. Do not use them with real funds.

We do not claim that this software is secure, audited, or production-ready, and no such
claim should be inferred from this repository.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately using GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository, or email the maintainers listed in `CODEOWNERS`.

Please include:

- A description of the issue and its impact.
- Reproduction steps or a proof of concept.
- Affected commit, contract, or file.
- Any suggested remediation.

We aim to acknowledge reports within **72 hours** and to provide a remediation timeline
after triage. We will credit reporters who wish to be named once a fix is released.

## In scope

- `contracts/factory` and `contracts/group` — authorization, custody, payout logic,
  fee calculation, round state transitions, storage/TTL handling.
- Any path that could move funds to an unintended recipient.
- Any path that could create a duplicate payout or duplicate contribution.
- Any path that allows arbitrary withdrawal by a creator, admin, backend, or treasury.

## Out of scope

- Stellar/Soroban network or core protocol vulnerabilities (report upstream).
- Issues in dependencies (report upstream; we track via `cargo audit` / `cargo deny`).
- Testnet-only deployment and operational issues with no security impact.
- Missing hardening that requires an already-compromised deployer key.

## Financial invariants

The following are **security-critical**. Any change to them requires human review and must
never be made silently:

| Invariant | Value |
|---|---|
| Protocol fee | `amount * 50 / 10_000` (0.50%) |
| Recipient amount | `amount - fee` |
| Contributions per member per round | exactly 1 |
| Payouts per round | exactly 1 |
| Token | configured USDC SAC only |
| Payout recipient | derived from immutable payout order |
| Arithmetic | integers only — never floating point |
| Arbitrary withdrawal | never permitted |

Chain state is authoritative. Off-chain systems never hold financial authority.

## Disclosure

We follow coordinated disclosure. Once a fix is available we will publish a security
advisory describing the issue, affected versions, and remediation.
