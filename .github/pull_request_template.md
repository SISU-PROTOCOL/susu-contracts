# Pull Request

## Summary

<!-- What does this change and why? -->

## Repository

- [ ] `susu-contracts`
- [ ] `susu-web`
- [ ] `susu-api`
- [ ] `susu-indexer`

## Type of change

- [ ] Bug fix
- [ ] Feature
- [ ] Refactor (no behavior change)
- [ ] Documentation
- [ ] CI / tooling
- [ ] Security hardening

## Financial & security impact

<!-- Be explicit. Reviewers depend on this section. -->

- [ ] This change does **not** affect financial behavior.
- [ ] This change **does** affect financial behavior — a maintainer has approved the
      approach in an issue, and the invariants below are preserved.

Invariants touched (leave unchecked if unaffected):

- [ ] Fee calculation (50 bps / 0.50%)
- [ ] Payout recipient selection / payout order
- [ ] Round advancement or completion
- [ ] Custody or authorization
- [ ] Token or amount validation
- [ ] Storage keys or TTL / archival behavior
- [ ] Upgrade or admin authority

If any invariant box above is checked, describe the change and its justification:

<!-- ... -->

## Database / migration impact

- [ ] No database or migration changes.
- [ ] Database or migration changes included.
      - [ ] RLS is enabled and policies are preserved (never silently disabled).
      - [ ] Grants follow least privilege; no unnecessary `anon`/`authenticated` access.
      - [ ] Security tests (pgTAP) added or updated.
      - [ ] Migration is reversible or has a documented forward-fix plan.

## Testing

<!-- What tests were added or updated? What did you run locally? -->

- [ ] New or updated tests cover the change, including negative paths.
- [ ] `format`, `lint`, `typecheck` pass.
- [ ] Test suites pass.
- [ ] Contract wasm build passes (contracts only).

## Secrets

- [ ] No secrets, private keys, service-role keys, or credentials are included.
- [ ] No secret values are logged or exposed to the browser.

## Checklist

- [ ] Docs updated to match the implementation (if behavior changed).
- [ ] `THREAT_MODEL.md` updated (if the change alters the threat surface).
- [ ] No claims of being audited, secure, or production-ready were added without evidence.
