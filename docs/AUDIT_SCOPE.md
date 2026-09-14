# Independent Review — Scope and Handover

> Phase 11. This is the material an independent reviewer needs to begin. It was written by the
> people who built the system, for a reviewer who did not, and it is deliberately unflattering
> where the truth is unflattering. Nothing here is a finding: a finding is something a reviewer
> concludes, and no review has happened yet.

## Why this document exists

A review that starts with the reviewer reading four repositories cold spends most of its budget
reconstructing what the system is. This document is the shortcut: what exists, what holds value,
what we already distrust about our own work, and which questions we cannot answer ourselves.

**Read the threat model with suspicion.** [`THREAT_MODEL.md`](THREAT_MODEL.md) describes what we
believe we defend against and how. It is our claim, not evidence. Where it asserts that a defence
exists, the useful review question is whether the code actually enforces it. Two review passes in
particular pay for themselves: whether every financial rule the threat model names is enforced
*on-chain* rather than by the frontend, and whether the off-chain components can be compromised
without moving funds.

## The engagement

**In scope:** the four components below, at the tagged baseline, plus their CI gates and their
database schemas (which live in migrations and are part of the shipped system, not an afterthought).

**The review we are asking for** is a security review of a non-custodial system holding other
people's money. Two things follow from "non-custodial" and both are load-bearing: the contracts are
the only thing standing between a user's funds and another user's, and everything else is
compromisable by design without that being a breach.

**What a reviewer should assume about our intentions:** we have tried to make the off-chain
components unable to cause financial harm even if fully compromised. If that assumption is wrong
anywhere, it is the most serious possible finding, because it invalidates the deployment model
rather than a single check.

**The baseline is a tag, not a branch.** Each repository is tagged **`audit-freeze-1`** at the
revision to review. The tags are annotated, so each records the commit it points at, and a tag does
not move — anything committed after it is out of scope. If a fix lands while the review is running,
say so and describe it; do not fold it in silently, because a review of a moving target reviews
nothing in particular.

| Component        | Language       | What it is                                     |
| ---------------- | -------------- | ---------------------------------------------- |
| `susu-contracts` | Rust / Soroban | Factory and Group contracts — the custody      |
| `susu-web`       | React / TS     | Browser client, wallet integration             |
| `susu-api`       | Node / Fastify | Read models, invites, profiles, wallet linking |
| `susu-indexer`   | Deno / TS      | Chain events → Postgres, on a schedule         |

## The system in one page

The protocol is a rotating savings scheme — a *susu* — where members contribute a fixed amount each
round and one member receives the whole pool per round, until everyone has received once. It is
implemented as two Soroban contracts on Stellar:

- **Factory** — deploys groups, holds protocol configuration (token, fee, treasury), and records
  which groups are genuine. It is how a client knows a `C…` address is a Susu group rather than a
  malicious contract wearing the same interface.
- **Group** — holds the members' USDC between contribution and payout. One group is one susu: fixed
  members, fixed amount, fixed round count, decided at creation and immutable once started.

Everything else exists to make that usable:

- **`susu-web`** builds and proposes transactions. It holds no key, and every write goes
  build → simulate → **user's wallet signs** → submit → confirm.
- **`susu-api`** serves everything the chain is not good at answering quickly: searchable group
  lists, invite codes, profile and notification state, and an account↔wallet binding. It holds a
  database credential and a Supabase service-role key, and **no Stellar key**.
- **`susu-indexer`** reads chain events on a timer and writes them into Postgres so the API can
  answer without an RPC round-trip. It holds a database credential and **no Stellar key**.

The asymmetry is the design: the components that are easiest to compromise — the ones on the public
internet with server credentials — are the ones that hold nothing worth stealing on-chain.

## Assets

| Asset                           | Where it lives                      | Why it is hard to take                     |
| ------------------------------- | ----------------------------------- | ------------------------------------------ |
| Member contributions (USDC)     | Group contract, between rounds      | No withdrawal path exists in the contract   |
| Correct payout, exactly once    | Group contract                      | Recipient derived from the immutable order  |
| Fee integrity (0.50%)           | Group → treasury                    | Fee is fixed at 50 bps and checked at boot  |
| Round state (one action/round)  | Group contract                      | On-chain guards, not UI state               |
| Member wallet keys              | The user's wallet                   | Never held by the protocol, at any layer    |
| Accounts and sessions           | Supabase Auth                       | Passwords hashed by the provider            |
| Account↔wallet binding          | `wallet_links`                      | Requires a signature over a server nonce    |

## Trust boundaries

**Trusted, and therefore the highest-value review target:**

1. **The Soroban contracts.** Everything financial is enforced here or it is not enforced.
2. **The Stellar network and the deployed Factory's group registry.** A client accepts an address as
   a group because the Factory says it is one.

**Untrusted with respect to funds — compromise must not move money:**

3. **`susu-web`.** Runs in a hostile environment (the browser); its own README says a user who
   bypasses the auth gate "would see an empty shell".
4. **`susu-api`.** Internet-facing, holds DB and service-role credentials. Trusted for
   *availability and privacy* of off-chain data, never for financial authority.
5. **`susu-indexer`.** Same. Its output is a cache, and the system is designed so a wrong cache is
   corrected rather than believed.
6. **Postgres and the browser's storage.** A hostile database can lie to the UI; it cannot make the
   chain accept a transaction.
7. **The configured RPC endpoint.** The frontend trusts it completely — no second source, no
   light-client verification. A malicious RPC can fabricate reads. It cannot forge a signature, but
   it can show a user a false state at the moment they decide to sign.

**Explicitly not trust boundaries, despite looking like them:** the `RequireAuth` route guard, the
members-only invite panel, and every "is this allowed" check in the UI. Each is documented in the
code as an affordance. If a reviewer finds one being relied on for a security property, that is a
finding about our documentation as much as our code.

## Off-chain threats

`THREAT_MODEL.md` covers the contracts in detail. These are the threats specific to the components
around them, and they are the ones least likely to have been reviewed before.

### A compromised frontend

*An attacker who controls the served JavaScript tries to redirect a payment.*

The frontend holds no key and cannot sign. It can only propose a transaction, which the user's
wallet displays and the contract constrains. An attacker who controls the *served bundle* is
therefore limited to presenting transactions the contract will reject, or to phishing the user into
approving something within the contract's rules. The mitigation is that no amount of frontend
compromise widens what the contract permits — which is a claim about the contracts, and belongs in
the contract review.

### A compromised or malicious API or indexer

*An attacker with database access rewrites balances, members, or recipients.*

Both hold credentials and no signing keys. They can lie in the UI's read models, but the UI is
built so that no decision is taken from indexed data: whether a user may contribute, and who is
paid, is read from the contract. Writes are re-read from the contract after mutation rather than
assumed. `THREAT_MODEL.md` records reconciliation as the repair mechanism for divergence.

**The residual risk is not the money, it is the decision.** A compromised read model can show a
false state at the moment a user chooses to sign. That is where the trust boundary actually sits,
and it is worth a reviewer's attention.

### Session theft through the browser

*An attacker who achieves script execution on the frontend origin takes the session.*

Supabase session tokens are stored in `localStorage` (the client sets no custom storage), so they
are reachable by any script on the origin, and the frontend repository contains no Content Security
Policy — headers are expected from the host, and the host's configuration is not in the repository.
The session grants access to off-chain data and to the ability to request wallet linking; it does
not grant the ability to sign.

### A linked wallet that belongs to someone else

*An attacker tries to bind a victim's Stellar address to their own account.*

Linking requires a signature over a server-issued, single-use, five-minute nonce, and both the
nonce and the binding are database-enforced (one wallet per account, one account per wallet, nonce
single-use). The signed message is rebuilt server-side from verified claims and is bound to the
account, the address and the network passphrase, so it cannot be replayed elsewhere. The address
must be an Ed25519 account (`G…`), so a contract address cannot be linked.

### Falsely claiming an address is a group

*An attacker registers an arbitrary contract address and uses it to mislead members.*

`POST /api/v1/groups` accepts a `C…` address **without checking the chain**, bounded by a 30-minute
expiry and a cap of five live registrations per account. This is deliberate and documented — it
exists so a creator can share an invite before the indexer has seen the group. It grants no
membership and no authority, because the contract decides who may join. But it does widen the set
of addresses an invite may name, and it is the single place where the system accepts an unverified
claim about the chain. **We would like this examined specifically.**

### Exhausting shared resources

*An attacker burns RPC quota or database connections through a legitimate-looking endpoint.*

`POST /api/v1/transactions/prepare` accepts a client-built envelope and simulates it, which costs
RPC quota. It validates aggressively (refuses fee bumps, multi-operation transactions, non-invoke
operations, and any contract outside the Factory and known groups). It also carries a rate-limit
budget of its own — twenty a minute, keyed by the session — rather than drawing on the global one
that every route and caller shares, because a single shared budget means one caller exhausting the
minute refuses everyone else while a caller with a second session is not slowed at all. The
remaining exposure is that every other route still shares the global 100 a minute.

### Lying about what was signed

*A malicious or compromised environment substitutes a different transaction for the one the user
believed they were approving.*

The frontend simulates before signing and refuses to reach the wallet if simulation fails, and it
now compares the envelope the wallet returns against the one it built: `signatureBase()` is exactly
the bytes a signer authorizes, so comparing it covers the source, fee, sequence, time bounds, memo
and every operation and argument. A wallet that returns anything else is refused and nothing is
submitted.

What remains is what the user *sees*. The app still does not display a decoded envelope, so the only
view of what is about to be approved is the wallet's own. The check guarantees the transaction is
ours; it cannot guarantee the user read it. `SECURITY.md` at the repository root lists transaction
substitution as in scope, and this is the honest state of the defence.

## What we already believe is weak

Ranked by how much we would want to be told, not by severity. None of these is a finding; they are
our own suspicions, offered so a reviewer can confirm or refute them cheaply.

1. **The API connects to Postgres as a role that bypasses RLS.** Row-level security is therefore a
   backstop for the *browser*, not for the API. Every query the API runs against user-owned rows
   must scope by the caller's `user_id` in application code, and that scoping is load-bearing rather
   than belt-and-braces. The modules we have read do this correctly; the review question is whether
   *all* of them do. A single missed `where` is a cross-user data leak, not a defence-in-depth
   failure.
2. **The unverified group registration above.** Deliberate, bounded, and still the weakest accepted
   claim in the system.
3. **The API's error and validation behaviour when Supabase is unreachable.** Token verification is
   a network call, so an outage makes every authenticated route return 401. This is chosen
   deliberately over failing open, and it means availability and authentication are coupled.
4. **Session tokens in `localStorage` with no CSP committed.** Also above. Mitigated heavily on the
   injection side; the storage choice itself remains the exposure.
5. **No in-app transaction preview, and the wallet is trusted to show what it signs.** The envelope
   a wallet returns is now compared against the one we built, so a substituted transaction cannot be
   submitted. What is still not guaranteed is that the user *read* it: the only decoded view of the
   transaction is the wallet's own.
6. **The global rate limiter still covers every other route.** The RPC-spending endpoint now carries
   its own per-session budget, but the rest of the surface shares a single 100-a-minute allowance,
   and no other route has a budget of its own.
7. **Database transport when TLS is unverified.** The API refuses a remote database with neither a
   CA nor an explicit opt-out, but the opt-out exists and is an acknowledged MITM gap.
8. **The TypeScript notification sweeper is never constructed by the server.** This one is
   deliberate — `pg_cron` owns the schedule so that derivation survives this service being down, and
   the sweeper is a documented manual entry point for deployments without `pg_cron` — but a reader
   who greps for its callers finds none and reasonably asks why. The expired-nonce reaper had the
   same shape and was **not** deliberate: it was written, tested, and never called, and has since
   been wired up. We would rather flag the pattern than have it re-derived.

## What we know is missing

Stated so it is not mistaken for an oversight, and so a reviewer does not spend budget on it:

- **Independent review has not happened.** This document is preparation for it, not a substitute.
- **Formal verification of the fee and payout arithmetic** has not been performed.
- **Storage archival and restoration paths** (as opposed to TTL extension) are not exercised
  end-to-end.
- **Fee sponsorship is not implemented**, deliberately: it would require a spending key in the
  service, and the service is currently designed to hold none.
- **No deployment or secret-injection configuration is committed to any repository.** How
  `DATABASE_URL`, the service-role key and the nonce secret are provisioned, rotated, and scoped in
  production is not reviewable from the code. We would rather say so than have it assumed.
- **There is no invite revocation endpoint**, despite `invite_links.revoked_at` existing in the
  schema.
- **Testnet only.** Mainnet writes are refused in code, and the API refuses to start on mainnet
  without an explicit flag. Mainnet readiness is a later phase with its own gate
  ([`MAINNET_READINESS.md`](MAINNET_READINESS.md)), which is checked by
  `scripts/check-mainnet-readiness.sh` rather than remembered. It is enforced in CI in
  `--mechanical-only` mode, so the invariant-to-test mapping and the frozen public interface cannot
  regress silently. The verdict there is still `NO-GO` and will remain so until this review is
  complete — the two are the same gate.

## How to run it

Each repository's `README.md` has the authoritative instructions; the shapes are:

- **`susu-contracts`** — Rust toolchain plus the Soroban target; `cargo test` runs the contract
  suite, which includes the invariants the threat model claims. No network needed.
- **`susu-web`** — pnpm; `pnpm dev` against Testnet, `pnpm test`, `pnpm build`. Requires a Supabase
  project and RPC access for anything beyond unit tests.
- **`susu-api`** — pnpm; `pnpm test`, `pnpm build`; needs a Postgres database and a Supabase project.
  The database guards run as SQL test files against a scratch database, and they test the guards
  themselves as well as the policies.
- **`susu-indexer`** — Deno; `deno test`, `deno task check`. The indexer is deployed as a Supabase
  Edge Function on a schedule, and its migrations are applied by hand.

Each repository's CI is the definition of "green": format, lint, typecheck, tests, plus a secret
scan and (where relevant) a dependency audit, an RLS guard and a bundle-credential scan. The CI
configuration is itself in scope — a gate that cannot fail is worth knowing about.

## Out of scope

- **The Stellar network, Soroban itself, and the USDC token contract.** Assumed correct.
- **Supabase as a platform** beyond what our configuration asks of it — our RLS policies, our
  migrations, our storage bucket rules.
- **The wallet extension.** Freighter is trusted to hold the key and to show what it signs.
- **Hosting and TLS.** Not committed to any repository; not reviewable here.
- **Governance, treasury operations, and key management** for the accounts that will hold
  production authority. They are not in these repositories.

## What we want out of the review

Beyond the standard report, four questions we genuinely cannot answer ourselves:

1. **Can any compromise of the API, the indexer, or the database move funds, or make a contract
   accept a transaction it should reject?** If yes, the deployment model is wrong rather than a
   check being missing.
2. **Is there any code path in either contract by which a member's contribution reaches anyone
   other than the address the payout order names?**
3. **Does the browser ever make a security decision that the contract is not independently
   enforcing?** The `RequireAuth` gate and the invite panel are documented as affordances; we want to
   know whether we missed one that is not.
4. **Where does our own threat model claim a defence the code does not implement?** We wrote the
   defence list, and we are the least reliable judges of our adherence to it.
