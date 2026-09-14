#!/usr/bin/env bash
#
# Mainnet readiness: verify what can be verified, and refuse to claim the rest.
#
# The readiness gate in docs/MAINNET_READINESS.md is a list of things that must
# be true. A list that someone ticks is not a gate — it is a record of optimism.
# This script replaces the ticks with evidence where evidence is possible, and
# names the items that genuinely require a human to attest to them, so that the
# two can never be confused for each other.
#
# It is read-only. It never deploys, never signs, never writes to a chain, and
# never changes a tracked file unless --record-interface is passed explicitly.
#
# Exit status:
#   0  every machine-checkable gate passed AND every attestation is recorded
#   1  at least one gate failed, or a required attestation is missing
#
# A non-zero exit means "do not deploy", not "this script is broken".
#
# Usage:
#   ./scripts/check-mainnet-readiness.sh              # everything
#   ./scripts/check-mainnet-readiness.sh --no-tests   # skip the (slow) test suite
#   ./scripts/check-mainnet-readiness.sh --mechanical-only
#       Structural checks only, for CI: invariants mapped, interface frozen, no
#       mainnet enabled by accident, fee cap, recorded USDC address. External
#       tools and the human attestations are reported but not enforced, because
#       CI enforces the tools separately and cannot audit or approve anything.
#       This is not a readiness verdict.
#   ./scripts/check-mainnet-readiness.sh --record-interface
#       Rewrite docs/mainnet-interface.txt from the current source. A deliberate
#       act: it invalidates the previous freeze and must be followed by re-review
#       of anything that changed.

set -euo pipefail

cd "$(dirname "$0")/.."

RUN_TESTS=1
RECORD_INTERFACE=0
MECHANICAL_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --no-tests) RUN_TESTS=0 ;;
    --record-interface) RECORD_INTERFACE=1 ;;
    --mechanical-only)
      # For CI. Checks everything a machine can check and treats the human
      # attestations as informational, so the verdict reflects only the parts
      # that are this repository's responsibility. It exists so that renaming an
      # invariant's test, or adding a third place that moves funds, or flipping a
      # mainnet switch, fails a build instead of quietly voiding a claim.
      MECHANICAL_ONLY=1
      ;;
    -h | --help)
      sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Output. Colour only when a terminal is watching, so logs stay readable.
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_PASS=$'\033[32m'; C_FAIL=$'\033[31m'; C_BLOCK=$'\033[33m'
  C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_PASS=''; C_FAIL=''; C_BLOCK=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

FAILURES=0
BLOCKED=0
CHECKS=0

pass() {
  CHECKS=$((CHECKS + 1))
  printf '  %s  %s\n' "${C_PASS}PASS${C_OFF}" "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf '  %s  %s\n' "${C_FAIL}FAIL${C_OFF}" "$1"
}

blocked() {
  CHECKS=$((CHECKS + 1))
  BLOCKED=$((BLOCKED + 1))
  printf '  %s %s\n' "${C_BLOCK}BLOCK${C_OFF}" "$1"
}

note() { printf '  %s  %s\n' "${C_DIM}----${C_OFF}" "$1"; }
section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_OFF"; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ---------------------------------------------------------------------------
# Header. The script's own hash is printed so a report can be tied to the exact
# revision of the checker that produced it — evidence is worthless if you cannot
# say what produced it.
# ---------------------------------------------------------------------------
REVISION="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
AUDIT_TAG="$(git rev-parse --verify --quiet 'audit-freeze-1^{commit}' 2>/dev/null || echo '')"

printf '%s\n' "=========================================================="
printf '%s\n' " Mainnet readiness — evidence report"
printf '%s\n' "----------------------------------------------------------"
printf ' checker sha256    %s\n' "$(hash_file "$0")"
printf ' repository        %s\n' "$(pwd)"
printf ' revision          %s (%s)\n' "${REVISION:0:12}" "$BRANCH"
printf ' recorded (UTC)    %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [ -n "$AUDIT_TAG" ]; then
  printf ' audit baseline    audit-freeze-1 = %s\n' "${AUDIT_TAG:0:12}"
  AHEAD="$(git rev-list --count "$AUDIT_TAG..HEAD" 2>/dev/null || echo '?')"
  printf ' commits since     %s\n' "$AHEAD"
else
  printf ' audit baseline    %s\n' "audit-freeze-1 is not present"
fi
printf '%s\n' "=========================================================="

# ---------------------------------------------------------------------------
# Contracts — the financial invariants.
#
# Each invariant is traced to the test that proves it. Invariant 10 is the
# exception: "no arbitrary withdrawal path exists" is not a behaviour that a test
# can demonstrate, it is a property of the code's shape, so it is checked by
# enumerating where funds can move at all.
# ---------------------------------------------------------------------------
section "Contracts — invariants"

GROUP_SRC="contracts/group/src/lib.rs"
GROUP_TESTS="contracts/group/src/test.rs"

if [ ! -f "$GROUP_SRC" ]; then
  fail "cannot find $GROUP_SRC — run this from the susu-contracts repository"
else
  # invariant id | statement | test that proves it ("STRUCTURAL" = see below)
  INVARIANTS=(
    "1|fee = pool * fee_bps / 10_000|fee_split_invariant_holds_across_many_pools"
    "2|recipient_amount = pool - fee|execute_payout_pays_the_recipient_from_the_immutable_order"
    "3|fee + recipient_amount == pool|fee_split_invariant_holds_across_many_pools"
    "4|exactly one contribution per member per round|contribute_rejects_a_duplicate_contribution_in_the_same_round"
    "5|exactly one payout per round|execute_payout_cannot_execute_the_same_round_twice"
    "6|configured amount only, and the configured token only|contribute_rejects_a_wrong_amount"
    "7|no early payout|execute_payout_waits_until_every_member_has_contributed"
    "8|recipient derives from the immutable payout order|execute_payout_pays_the_recipient_from_the_immutable_order"
    "9|payouts + fees <= valid contributions|every_member_receives_exactly_one_payout"
    "10|no arbitrary withdrawal, by any actor|STRUCTURAL"
    "11|the final round completes exactly once|final_round_completes_the_group_exactly_once"
  )

  MISSING_INVARIANTS=0
  for entry in "${INVARIANTS[@]}"; do
    IFS='|' read -r id statement test_name <<<"$entry"

    if [ "$test_name" = "STRUCTURAL" ]; then
      # Checked below, by enumerating the contract's fund-moving code paths.
      continue
    fi

    if [ ! -f "$GROUP_TESTS" ]; then
      fail "invariant $id: no test file at $GROUP_TESTS"
      MISSING_INVARIANTS=$((MISSING_INVARIANTS + 1))
      continue
    fi

    if grep -qE "^fn ${test_name}\(\)" "$GROUP_TESTS"; then
      note "invariant $id -> $test_name"
    else
      fail "invariant $id ($statement): no test named '$test_name' exists"
      MISSING_INVARIANTS=$((MISSING_INVARIANTS + 1))
    fi
  done

  if [ "$MISSING_INVARIANTS" -eq 0 ]; then
    pass "every behavioural invariant resolves to a test that exists"
  fi

  # Invariant 10, structurally. Funds leave the Group only through a token
  # transfer, so the whole of the question "can anything take the money" is
  # answered by "which functions contain a transfer". If that set is exactly
  # {contribute, execute_payout}, there is no other way out — no admin call, no
  # rescue function, no upgrade hook. A new transfer site anywhere else is a
  # finding, not a refactor.
  TRANSFER_SITES="$(awk '
    /^[[:space:]]*pub fn / { fn = $0; sub(/^[[:space:]]*pub fn /, "", fn); sub(/[(<].*$/, "", fn) }
    /\.transfer\(/ { print fn }
  ' "$GROUP_SRC" | sort -u)"

  EXPECTED_SITES=$'contribute\nexecute_payout'

  if [ "$TRANSFER_SITES" = "$EXPECTED_SITES" ]; then
    note "invariant 10 -> funds move only in: contribute, execute_payout"
    pass "no withdrawal path outside contribute and execute_payout"
  else
    fail "invariant 10: unexpected set of functions that move funds"
    printf '        expected: %s\n' "$(printf '%s' "$EXPECTED_SITES" | tr '\n' ' ')"
    printf '        found:    %s\n' "$(printf '%s' "$TRANSFER_SITES" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# Contracts — the interface is frozen.
#
# "Interface frozen" has to mean something checkable, or it means nothing. The
# public entry points are recorded; if they change, this fails until someone
# re-records them on purpose and re-reviews what moved.
# ---------------------------------------------------------------------------
section "Contracts — interface freeze"

INTERFACE_FILE="docs/mainnet-interface.txt"

current_interface() {
  for contract in group factory; do
    src="contracts/$contract/src/lib.rs"
    [ -f "$src" ] || continue
    # Only indented `pub fn` — that is, inside the `#[contractimpl]` block, which
    # is what a caller can actually invoke. A `pub fn` at column 0 is a
    # module-level helper (the Factory's `group_salt`, for one) and is not part
    # of the contract interface, so a change to it is not an interface change.
    grep -oE '^[[:space:]]+pub fn [a-z_0-9]+' "$src" |
      sed -E 's/.*pub fn //' |
      sort |
      sed "s/^/$contract: /"
  done
}

if [ "$RECORD_INTERFACE" -eq 1 ]; then
  current_interface >"$INTERFACE_FILE"
  echo
  echo "Recorded the current interface to $INTERFACE_FILE."
  echo "This invalidates the previous freeze: anything that changed must be reviewed."
  exit 0
fi

if [ ! -f "$INTERFACE_FILE" ]; then
  blocked "no recorded interface at $INTERFACE_FILE (run with --record-interface)"
elif diff -q <(current_interface) "$INTERFACE_FILE" >/dev/null 2>&1; then
  COUNT="$(wc -l <"$INTERFACE_FILE" | tr -d ' ')"
  pass "public entry points match the recorded interface ($COUNT functions)"
else
  fail "the public interface has changed since it was recorded"
  diff <(current_interface) "$INTERFACE_FILE" | sed 's/^/        /' || true
fi

# ---------------------------------------------------------------------------
# Contracts — the test suite, and the dependency audit.
# ---------------------------------------------------------------------------
section "Contracts — suite and dependencies"

if [ "$RUN_TESTS" -eq 1 ]; then
  note "running cargo test --workspace (this is the slow part)"
  if TEST_OUT="$(cargo test --workspace 2>&1)"; then
    PASSED="$(printf '%s\n' "$TEST_OUT" |
      grep -oE 'test result: ok\. [0-9]+ passed' |
      grep -oE '[0-9]+' |
      awk '{total += $1} END {print total + 0}')"
    pass "the contract test suite passes ($PASSED tests)"
  else
    fail "the contract test suite does not pass"
    printf '%s\n' "$TEST_OUT" | grep -E '^(error|failures:)' -A 5 | sed 's/^/        /' || true
  fi
else
  note "skipped cargo test --workspace (--no-tests)"
fi

# Both are required, and a missing tool is a failure rather than a skip: the
# gate says "dependency audit clean", and an audit that did not run is not clean.
#
# In --mechanical-only mode these are skipped, because CI already enforces them
# in the security job — which has the tools installed and does not need them run
# twice. Skipping them here is not a relaxation of the gate: the full run still
# requires them, and a missing tool there is still a failure.
if [ "$MECHANICAL_ONLY" -eq 1 ]; then
  note "cargo audit and cargo deny: enforced by the CI security job"
else
  if command -v cargo-audit >/dev/null 2>&1; then
    if cargo audit >/dev/null 2>&1; then
      pass "cargo audit reports no known vulnerabilities"
    else
      fail "cargo audit reports advisories"
      cargo audit 2>&1 | grep -E '^(error|warning|ID)' | head -20 | sed 's/^/        /' || true
    fi
  else
    fail "cargo-audit is not installed, so the audit cannot be shown to be clean"
  fi

  if command -v cargo-deny >/dev/null 2>&1; then
    if cargo deny check >/dev/null 2>&1; then
      pass "cargo deny accepts licences, bans, sources and advisories"
    else
      fail "cargo deny reports a problem"
      cargo deny check 2>&1 | tail -25 | sed 's/^/        /' || true
    fi
  else
    fail "cargo-deny is not installed, so the policy cannot be shown to hold"
  fi
fi

# ---------------------------------------------------------------------------
# Configuration.
# ---------------------------------------------------------------------------
section "Configuration"

# The fee is the protocol's only revenue and the thing members are most exposed
# to, so its cap is checked at the source rather than trusted to a config file.
FEE_CAP_OK=1
for contract in group factory; do
  src="contracts/$contract/src/lib.rs"
  if grep -qE '^pub const MAX_FEE_BPS: u32 = 50;' "$src"; then
    note "$contract: MAX_FEE_BPS = 50"
  else
    fail "$contract: MAX_FEE_BPS is not 50"
    FEE_CAP_OK=0
  fi
done
if [ "$FEE_CAP_OK" -eq 1 ]; then
  pass "the protocol fee cap is 0.50% in both contracts"
fi

# The safety switches exist to make mainnet impossible by accident. They are
# checked *here* only in their default state: if a repository has mainnet turned
# on in what it ships, that is the accident this is looking for.
MAINNET_SWITCHES=0
check_switch_off() {
  local file="$1" pattern="$2" what="$3"
  [ -f "$file" ] || return 0
  if grep -qE "$pattern" "$file"; then
    fail "$what is enabled in a committed file ($file)"
    MAINNET_SWITCHES=$((MAINNET_SWITCHES + 1))
  fi
}

check_switch_off "../susu-api/.env.example" '^ALLOW_MAINNET=true' "ALLOW_MAINNET"
check_switch_off "../susu-indexer/.env.example" '^ALLOW_MAINNET=true' "ALLOW_MAINNET"
check_switch_off "../susu-web/.env.example" '^VITE_STELLAR_NETWORK=mainnet' "the web mainnet network"
check_switch_off ".env.mainnet" '^ALLOW_MAINNET=true' "a committed mainnet env file"

if [ "$MAINNET_SWITCHES" -eq 0 ]; then
  pass "no committed configuration enables mainnet"
fi

# The mainnet USDC address is the one value that, if wrong, sends real money to
# the wrong contract. It is recorded in the readiness doc and checked here so the
# two cannot drift apart.
readonly VERIFIED_MAINNET_USDC_SAC="CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75"
if grep -qF "$VERIFIED_MAINNET_USDC_SAC" docs/MAINNET_READINESS.md 2>/dev/null; then
  note "mainnet USDC SAC: $VERIFIED_MAINNET_USDC_SAC"
  note "issuer:           GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"
  pass "the recorded mainnet USDC address matches the verified one"
else
  fail "docs/MAINNET_READINESS.md does not record the verified mainnet USDC address"
fi

# ---------------------------------------------------------------------------
# Secrets.
# ---------------------------------------------------------------------------
section "Secrets"

if [ "$MECHANICAL_ONLY" -eq 1 ]; then
  note "gitleaks history scan: enforced by the CI security job"
elif command -v gitleaks >/dev/null 2>&1; then
  if gitleaks git . --redact --exit-code 1 >/dev/null 2>&1; then
    pass "gitleaks finds no secrets in the full git history"
  else
    fail "gitleaks reports a potential secret"
  fi
else
  fail "gitleaks is not installed, so the history cannot be shown to be clean"
fi

# ---------------------------------------------------------------------------
# Attestations — the part that cannot be automated.
#
# These are the gates that need a person to have done something and to say so.
# They are read from a file rather than a prompt because a prompt can be answered
# by anyone, including whoever is impatient; a recorded attestation names who
# said it and when, and can be checked afterwards.
# ---------------------------------------------------------------------------
section "Attestations (human)"

ATTESTATION="docs/mainnet-attestation.md"

if [ ! -f "$ATTESTATION" ]; then
  if [ "$MECHANICAL_ONLY" -eq 1 ]; then
    note "no attestation recorded at $ATTESTATION (informational in this mode)"
  else
    blocked "no attestation recorded at $ATTESTATION"
    note "copy docs/mainnet-attestation.example.md and fill it in honestly"
    note "until it exists and is complete, the gate is not satisfied"
  fi
else
  attest() {
    local key="$1" what="$2"
    local value
    value="$(grep -E "^${key}:" "$ATTESTATION" | head -1 | sed -E "s/^${key}:[[:space:]]*//" || true)"

    if [ -z "$value" ] || printf '%s' "$value" | grep -qE '^<.*>$|^TBD$|^TODO$|^none$'; then
      if [ "$MECHANICAL_ONLY" -eq 1 ]; then
        note "$what — not attested"
      else
        blocked "$what — not attested"
      fi
    else
      note "$what: $value"
    fi
  }

  attest "audit-completed" "independent security review completed"
  attest "audit-findings-resolved" "findings resolved or accepted with rationale"
  attest "admin-multisig" "admin authority is an M-of-N multisig"
  attest "treasury-address" "treasury is a dedicated address"
  attest "identities-separate" "mainnet identities are separate from testnet"
  attest "monitoring-live" "monitoring and alerting are live on mainnet"
  attest "runbook-rehearsed" "the incident runbook has been rehearsed"
  attest "legal-review" "legal and compliance review completed"
  attest "approved-by" "explicit human approval"
  attest "approval-date" "date of that approval"

  pass "an attestation file exists (its contents are the attestor's claim — each field above is what the gate actually reads)"
fi

# ---------------------------------------------------------------------------
# Verdict.
# ---------------------------------------------------------------------------
printf '\n%s\n' "=========================================================="
printf ' checks run        %s\n' "$CHECKS"
printf ' failed            %s\n' "$FAILURES"
if [ "$MECHANICAL_ONLY" -eq 1 ]; then
  printf ' blocked (human)   %s (informational: --mechanical-only)\n' "$BLOCKED"
else
  printf ' blocked (human)   %s\n' "$BLOCKED"
fi
printf '%s\n' "----------------------------------------------------------"

if [ "$FAILURES" -gt 0 ] || { [ "$MECHANICAL_ONLY" -eq 0 ] && [ "$BLOCKED" -gt 0 ]; }; then
  printf ' %sNO-GO%s — mainnet deployment is not authorised.\n' "$C_FAIL" "$C_OFF"
  if [ "$FAILURES" -gt 0 ]; then
    printf '        %s machine-checkable gate(s) failed.\n' "$FAILURES"
  fi
  if [ "$MECHANICAL_ONLY" -eq 0 ] && [ "$BLOCKED" -gt 0 ]; then
    printf '        %s item(s) need a human attestation.\n' "$BLOCKED"
  fi
  printf '%s\n' "=========================================================="
  exit 1
fi

if [ "$MECHANICAL_ONLY" -eq 1 ]; then
  printf ' %sMECHANICAL CHECKS PASS%s — the parts this repository controls are intact.\n' \
    "$C_PASS" "$C_OFF"
  printf ' This is not a readiness verdict. The human attestations are still required,\n'
  printf ' and mainnet remains blocked until they are recorded.\n'
else
  printf ' %sGO%s — every gate is satisfied.\n' "$C_PASS" "$C_OFF"
  printf ' Both people who read this report should agree it is accurate before\n'
  printf ' anything is deployed. A script can check the parts that are mechanical;\n'
  printf ' it cannot check that the attestations are true.\n'
fi
printf '%s\n' "=========================================================="
