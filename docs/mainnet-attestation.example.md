# Mainnet attestation — TEMPLATE

Copy this file to `docs/mainnet-attestation.md` and fill it in. That file is what
`scripts/check-mainnet-readiness.sh` reads, and it does not exist until someone creates it.

**Every value below is a claim by a person, not a verification.** The readiness script checks that
each field is present and not a placeholder; it cannot check that it is true. Filling this in is the
act of taking responsibility for the statement, which is why it is a file with a name and a date on
it rather than a checkbox.

Leave a line as-is (or delete it) and the corresponding gate stays `BLOCK`ed and the verdict stays
`NO-GO`.

**Do not fill this in until the thing being attested has actually happened.** An attestation that
says an audit is complete when it is not is worse than a blocked gate, because the gate's whole
purpose is to be the thing that cannot be talked around.

---

```
audit-completed: <date the independent review was delivered, or leave as-is>
audit-findings-resolved: <"all resolved", or a list of accepted findings with rationale — an accepted finding with no rationale is not accepted, it is deferred>
audit-reviewer: <who performed it, and a reference to their report>
admin-multisig: <M-of-N and the signer public keys, or the account's on-chain signer configuration>
admin-multisig-verified-on: <date, and how it was read back from the chain>
treasury-address: <the dedicated Mainnet treasury account, never a personal wallet>
identities-separate: <how Mainnet identities are kept distinct from Testnet, and confirmation no key material is reused>
monitoring-live: <what is watched on Mainnet, where alerts go, and the date each was proven to fire>
runbook-rehearsed: <who rehearsed the pause procedure, when, and on which network>
deployed-artifact: <sha256 of both wasm artifacts, and confirmation of a second independent rebuild>
usdc-address-checked: <confirmation that CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75 was verified against Circle's published addresses>
legal-review: <outcome, jurisdiction, and who performed it>
approved-by: <name — the person accountable for this deployment, not a team or a role>
approval-date: <date>
```

## Notes on the fields that are easiest to get wrong

- **`audit-findings-resolved`** — "all resolved" is a strong claim. If any finding was accepted
  rather than fixed, it belongs here with the reason it is acceptable, in the same sentence. A
  reader should be able to disagree with the reasoning, which is not possible if only the conclusion
  is recorded.
- **`admin-multisig`** — the point is that no single key can change the fee or the treasury for every
  future group. An account whose master key alone can still sign is a single-key account whatever
  else is configured, so state the thresholds and whether the master key can act alone.
- **`monitoring-live`** — "we have alerts" is not the claim. The claim is that an alert was seen to
  fire on Mainnet. Record when that happened.
- **`deployed-artifact`** — the review covers a revision, and the gate is only meaningful if the thing
  deployed is what was reviewed. Two people building independently and getting the same hash is the
  evidence; one person's build is not.
- **`approved-by`** — a name. If something goes wrong, this is the line that says who decided.
