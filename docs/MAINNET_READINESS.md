# Mainnet Readiness — susu-contracts

> **Status: BLOCKED.**
>
> Mainnet deployment is manual, requires explicit human approval, and must never be automated or
> performed by CI. It must not happen until every gate below is satisfied **with evidence** — a
> ticked box is not evidence, and this document deliberately does not contain any.

## How this gate is checked

A checklist that a person ticks records optimism. So the mechanical parts are checked by a script,
and the parts that need a person are recorded as attestations that name who said it and when:

```bash
./scripts/check-mainnet-readiness.sh          # full run, including the test suite
./scripts/check-mainnet-readiness.sh --no-tests
```

It exits non-zero while anything is unmet, and prints a report that distinguishes three states:

| State     | Meaning                                                                     |
| --------- | --------------------------------------------------------------------------- |
| `PASS`    | A machine checked it, and it holds                                              |
| `FAIL`    | A machine checked it, and it does not hold                                      |
| `BLOCK`   | It cannot be verified mechanically; a person must attest to it in writing         |

**The script cannot pass the gate on its own**, and that is the point. Attestations come from
[`mainnet-attestation.md`](mainnet-attestation.example.md), which does not exist until someone
honestly fills it in. Until then every attestation item is `BLOCK` and the verdict is `NO-GO`.

The report prints the checker's own SHA-256 and the current revision, so a report can always be tied
to the code and the checker that produced it.

## Machine-verified gates

Checked by `scripts/check-mainnet-readiness.sh`. Each one fails loudly if it regresses.

### Contracts

- The full test suite passes (`cargo test --workspace`), on every negative path as well as the happy
  ones.
- **Every financial invariant resolves to a test that exists.** The eleven invariants in
  [`CONTRACT_SPEC.md`](CONTRACT_SPEC.md#invariants) are mapped to named tests in the checker, so
  renaming or deleting one fails the gate rather than quietly voiding the claim. Invariant 10 is the
  exception and is handled structurally — see below.
- **No arbitrary withdrawal path exists.** This is not a behaviour a test can demonstrate; it is a
  property of the code's shape. Funds can only leave a Group through a token transfer, so the checker
  enumerates every transfer site in the Group source and requires the set to be exactly
  `{contribute, execute_payout}`. A third transfer site anywhere — an admin rescue, a migration hook,
  an upgrade path — is a finding, not a refactor.
- **The contract interface is frozen.** The public entry points are recorded in
  [`mainnet-interface.txt`](mainnet-interface.txt) and the checker diffs against them. `pub fn` at
  column zero is a module-level helper and is not part of the interface. Re-recording is deliberate:
  `./scripts/check-mainnet-readiness.sh --record-interface` invalidates the freeze, and whatever
  moved must be reviewed again.
- Dependency policy holds: `cargo audit` clean, `cargo deny check` clean. A missing tool is a
  **failure**, not a skip — an audit that did not run is not a clean audit.

### Configuration

- `MAX_FEE_BPS == 50` in both contracts, so the protocol can never charge more than 0.50%.
- **No committed configuration enables Mainnet.** Checked in every `.env.example` and for a stray
  `.env.mainnet`. The safety switches exist so that Mainnet cannot happen by accident, and this is
  the check that they are still off.
- The recorded Mainnet USDC address matches the verified value (below).

### Secrets

- `gitleaks` finds no secrets in the full git history. A missing tool is a failure, for the same
  reason as above.

## Human-attested gates

These cannot be verified by reading code. Each requires a field in
[`mainnet-attestation.md`](mainnet-attestation.example.md), written as a claim by a named person.

- [ ] **Independent security review completed**, and every finding resolved or explicitly accepted
      with rationale. See [`AUDIT_SCOPE.md`](AUDIT_SCOPE.md) for the scope and the baseline tag.
- [ ] **Admin authority is an M-of-N multisig**, not a single key. The Factory's admin can change the
      fee and treasury and pause new group creation; a single key that can move the fee is a single
      point of failure for every future group. The concrete procedure: the admin account's
      signers and thresholds are set with `set_options`, the master key weight is reduced to zero or
      a threshold that requires the other signers, and the resulting configuration is verified
      on-chain with `stellar account show` before deployment.
- [ ] **Treasury is a dedicated address**, not a personal wallet, and it is separate from the admin
      and the deployer.
- [ ] **Mainnet identities are separate from Testnet** — different deployer, admin and treasury
      accounts, different RPC endpoints, different contract IDs, no reuse of any key material.
- [ ] **Monitoring and alerting are live on Mainnet** before the first group is created. The indexer's
      health check and alerts are Testnet-verified; they must be pointed at Mainnet and proven to
      fire there.
- [ ] **The incident runbook has been rehearsed**, not merely written. Pausing new group creation is
      the one lever that exists; whoever is on call must have actually exercised it.
- [ ] **Legal and compliance review** for the intended model and jurisdictions.
- [ ] **Explicit human approval**, recorded with a name and a date.

## The deployed artifact must be the audited artifact

The gate means nothing if the wasm deployed to Mainnet was not built from the revision that was
reviewed. Nothing in the repository can prove this on its own, so it is a procedure rather than a
check:

1. Check out the audited tag (`audit-freeze-1`).
2. Build with `./scripts/build-contracts.sh` on a machine that has not been used for anything else,
   and record the SHA-256 of both wasm files.
3. Compare those hashes against a rebuild performed by a second person. A difference means the build
   is not reproducible and the audit does not cover what would be deployed.
4. Deploy those exact artifacts, and record the deployed wasm hash read back from the chain.

Any source commit after the tag must be reviewed before it can be deployed. This is the reason the
baseline is a tag and not a branch.

## Verified Mainnet addresses

These are the only Mainnet values recorded here, and they are checked by the readiness script.

| What | Value |
| ---- | ----- |
| USDC issuer (Circle) | `GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN` |
| USDC Stellar Asset Contract | `CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75` |

**Verified against two independent sources** — Stellar's own developer documentation (x402 payments
reference) and Circle's published USDC contract addresses — rather than taken from a single page or
from memory. The Testnet values the project already uses
(`CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA`, issued by
`GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5`) were confirmed by the same sources,
which is worth having checked rather than assumed.

The two must never be mixed: pointing a client at the Testnet SAC on Mainnet, or the reverse, is a
configuration error with no on-chain guard against it.

## Mainnet configuration, and how it is not Testnet

Verified against Stellar's own network documentation rather than assumed. These are the things that
would otherwise be discovered painfully, one at a time, during a deployment.

- **There is no public Mainnet RPC operated by the SDF.** Testnet has
  `https://soroban-testnet.stellar.org`; Mainnet has no equivalent, and a hostname like
  `soroban-mainnet.stellar.org` is not a real endpoint. Mainnet access requires a **third-party
  provider or a self-hosted RPC instance**. Choosing one, and paying for the capacity, is an
  outstanding prerequisite that has not been done — and it is a dependency on an external service
  seeing every Mainnet transaction this protocol makes.
- **Network passphrase:** `Public Global Stellar Network ; September 2015`.
- **There is no Friendbot on Mainnet.** `stellar keys generate --fund`, which `deploy-testnet.sh`
  relies on for every identity, is Testnet-only. Mainnet identities must be funded from existing
  accounts. So the Mainnet path **cannot be a small variation of the Testnet script** — it needs its
  own procedure, and that procedure does not exist yet.
- **Explorer:** `https://stellar.expert/explorer/public`, not `.../testnet`.

One caveat worth stating plainly, because it is easy to over-read: `assertRpcMatchesNetwork` in the
web client refuses only *explicit contradictions* — `testnet` in a URL configured as Mainnet, or the
reverse — so that legitimate third-party providers are not rejected. A Mainnet RPC URL containing
neither word is accepted. That check catches the common mistake; it is **not** proof that a URL is a
Mainnet endpoint.

What the client does get right is the part that matters most: the network, passphrase and explorer
base URL are all derived from validated configuration, and `assertNetworkAllowsWrites` refuses every
Mainnet write at a single point. A misconfigured RPC URL cannot become a Mainnet transaction.

## What "controlled launch" can and cannot mean

Worth being precise about, because "controlled launch" implies a control the contracts do not
provide.

**The Factory can pause new group creation.** `pause()` / `unpause()` are admin-only, and pausing
cannot block a contribution, a payout, or anything inside an existing group. So the only lever is at
the boundary: **how many groups, and which, get created.**

**There is no cap on group size or on total value locked.** `create_group` accepts any contribution
amount and any capacity up to `MAX_MEMBERS`, with no protocol-level ceiling and no per-creator
limit. A group's members are exposed to exactly what they agreed to among themselves — the contract
enforces that, but it does not bound it.

So a controlled Mainnet launch means, concretely:

- Launch paused, or unpause deliberately for a named set of creators, and pause again.
- Choose the launch cohort by hand; there is no allowlist in the contracts to lean on.
- Watch the indexer's alerts and the treasury balance, and be willing to pause again.

Anyone describing this as a capped or permissioned launch should be corrected: the contracts are
permissionless by design, and the only control is the one an admin exercises at the door.

## Explicit statements

- This software **has not been audited**. The gate above cannot be satisfied while that is true.
- No claim of being secure, audited, or production-ready is made or implied.
- Mainnet deployment will not be performed by CI or by an autonomous agent.
- **Until `./scripts/check-mainnet-readiness.sh` exits zero with an honest attestation behind it, the
  answer to "is Mainnet ready?" is no.**

## Remaining unknowns

- Formal verification of the fee and payout arithmetic is not planned.
- Compliance posture for the target jurisdictions is not assessed.
- Build reproducibility has not been demonstrated, so the audited-artifact procedure above is a
  procedure that has not yet been run.
- **No Mainnet RPC provider has been chosen**, so the availability and cost of the dependency that
  would serve every Mainnet read and write is unknown.
- **No Mainnet deployment procedure exists.** `deploy-testnet.sh` refuses any network but Testnet by
  design, and its identity funding cannot work on Mainnet. Writing that procedure is deliberately
  deferred until the audit is done — it should be reviewed alongside the contracts it deploys, not
  written before them.
- The multisig procedure described above has not been performed or tested on either network.
