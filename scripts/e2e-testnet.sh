#!/usr/bin/env bash
#
# End-to-end lifecycle check against Stellar Testnet.
#
# Drives a real deployed Factory through the canonical reference scenario:
# 3 members x 10 USD. It creates a group, joins three members, starts it,
# contributes and pays out every round, and asserts the exact resulting token
# balance changes, including the 0.50% treasury fee.
#
# Testnet only. This never touches Mainnet and never touches a real asset.
#
# The script is idempotent and safe to re-run: identities are reused, the test
# asset is deployed only once, and assertions are expressed as balance *deltas*
# so that running it repeatedly produces the same result.
#
# It also asserts the refusals the contracts are expected to make: wrong amount,
# wrong round, duplicate contribution, early payout, over-capacity joins and
# similar. Each case names the exact contract error it must be refused with.
# Those checks are simulated only, so they cannot move funds and cannot pass by
# accident on a transaction that silently changed state.
#
# Testnet RPC intermittently times out or resets the connection, so submissions
# are retried on transient transport failures. The retry is careful about the
# difference between failing before signing (nothing was submitted, always safe
# to retry) and failing after signing (the transaction may already be live).
# See `stellar_tx` below.
#
# Usage:
#   ./scripts/e2e-testnet.sh
#
# Token selection
# ---------------
# By default this provisions a *test* asset (a Stellar classic asset issued by a
# throwaway testnet identity) and mints to the members. That is what makes the
# run fully automated: Circle's Testnet USDC issuer is the only account that can
# mint USDC, so Testnet USDC cannot be conjured programmatically.
#
# To run the same scenario against Circle's Testnet USDC SAC, export TOKEN_SAC
# with the USDC SAC address recorded in .env.example (STELLAR_TESTNET_USDC_SAC)
# and fund the three member accounts from Circle's faucet first. The lifecycle
# and assertions are identical; only the token differs. In that mode the script
# will not create trustlines or mint, and it will assert the same deltas.

set -euo pipefail

# ---------------------------------------------------------------------------
# Guard against being edited while it runs.
#
# Bash reads a script lazily, by byte offset, so editing one mid-run makes it
# execute misaligned content: a fragment of a comment becomes a command, and the
# behaviour that follows is arbitrary rather than merely wrong. That happened
# once here, on a run that was moving real test funds and asserting financial
# invariants. Nothing in the language detects it.
#
# So the file's hash is captured at startup and re-checked on exit. A mismatch
# means the run executed something nobody wrote, so the run fails loudly instead
# of reporting an outcome that cannot be trusted.
#
# The path is made absolute first, because the `cd` below would otherwise make a
# relative `$0` resolve somewhere else.
# ---------------------------------------------------------------------------
SCRIPT_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# `sha256sum` on Linux, `shasum` on macOS.
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

SCRIPT_HASH="$(hash_file "$SCRIPT_SELF")"

verify_script_unchanged() {
  local current
  current="$(hash_file "$SCRIPT_SELF")"
  if [ "$current" != "$SCRIPT_HASH" ]; then
    echo >&2
    echo "error: $SCRIPT_SELF was modified while it was running." >&2
    echo "       Bash reads scripts by byte offset, so this run executed content" >&2
    echo "       that is neither the old nor the new version. Its result cannot" >&2
    echo "       be trusted; re-run with the file left untouched." >&2
    exit 1
  fi
}
trap verify_script_unchanged EXIT

cd "$(dirname "$0")/.."

NETWORK="${STELLAR_NETWORK:-testnet}"
if [ "$NETWORK" != "testnet" ]; then
  echo "error: this script only runs against testnet (got STELLAR_NETWORK=$NETWORK)." >&2
  exit 1
fi

# Canonical reference scenario.
ONE_USDC=10000000                    # 7 decimals, as used by Soroban asset contracts
CONTRIBUTION=$((10 * ONE_USDC))      # 10 UDS per member per round
CAPACITY=3
FREQUENCY=604800                     # one week, nominal
ROUNDS=3
MEMBER_COUNT=3
INITIAL_MINT=$((100 * ONE_USDC))     # 100 UDS per member, enough for several runs

EXPECTED_FEE_PER_ROUND=$((CONTRIBUTION * CAPACITY * 50 / 10000))  # 0.15 UDS
EXPECTED_RECIPIENT=$((CONTRIBUTION * CAPACITY - EXPECTED_FEE_PER_ROUND))
EXPECTED_MEMBER_DELTA=$((EXPECTED_RECIPIENT - ROUNDS * CONTRIBUTION))  # -0.15 UDS
EXPECTED_TREASURY_DELTA=$((ROUNDS * EXPECTED_FEE_PER_ROUND))           #  0.45 UDS

# ---------------------------------------------------------------------------
# Load deployment addresses written by scripts/deploy-testnet.sh
# ---------------------------------------------------------------------------
if [ ! -f .env.testnet ]; then
  echo "error: .env.testnet not found. Run ./scripts/deploy-testnet.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1091
set -a; . ./.env.testnet; set +a

FACTORY_ID="${FACTORY_CONTRACT_ID:?FACTORY_CONTRACT_ID missing from .env.testnet}"
TREASURY_ADDR="${SUSU_TREASURY_PUBLIC:?SUSU_TREASURY_PUBLIC missing from .env.testnet}"
DEPLOYER="${SUSU_DEPLOYER_IDENTITY:-susu-testnet-deployer}"

echo "==> Factory $FACTORY_ID"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Contract error codes that mean "the intended change is already in place".
# Space-separated. A retry that hits one of these is a success, not a failure.
TX_OK_ERRORS=""
# Set to 1 for a command that is idempotent by nature, so it is safe to retry
# even when the first attempt failed *after* signing.
TX_RETRY_AFTER_SIGNING=0

# A contract refusal is deterministic: the same call fails the same way forever,
# so retrying it cannot help. The CLI renders these as `Error(Contract, #N)`.
#
# Everything else that fails comes from the toolchain or the network: timeouts,
# connection resets, `client error (Connect)`, `client error (SendRequest)`, a
# 502 from the RPC. Those are worth another attempt.
#
# The classification is by exclusion, not by an allowlist of transport phrases,
# because those phrases are unbounded: every outage so far has produced a new
# one, and each new one silently turned a retryable blip into a hard failure.
is_contract_refusal() {
  printf '%s' "$1" | grep -qE 'Error\(Contract, #[0-9]+\)'
}

# Run a transaction, retrying transport failures.
#
# The Testnet RPC intermittently times out or resets the connection. Those
# failures come in two forms, and they are not equally safe to retry:
#
#   - Failing before signing (during simulation): nothing was submitted, so a
#     retry cannot duplicate anything.
#   - Failing after signing: the transaction may already have been accepted, so
#     a blind retry could apply it twice. A caller whose intent is idempotent
#     declares the error that means "already done" (TX_OK_ERRORS), or marks the
#     command as idempotent (tx_idempotent), and a retry is then safe.
#
# Anything that is not a transient transport failure is surfaced in full,
# because a `--quiet` style silent exit would hide a genuine contract rejection.
#
# `--quiet` is deliberately not used anywhere here: it also swallows error
# messages, turning a real failure into an unexplained `exit 1`.
stellar_tx() {
  local attempt=1
  local max_attempts=3
  local out
  local code

  while :; do
    if out=$("$@" 2>&1); then
      printf '%s\n' "$out"
      return 0
    fi
    code=$?

    # A retry that reports the change is already in place means our earlier
    # attempt landed. Treat the desired end state as reached.
    local tolerated
    for tolerated in $TX_OK_ERRORS; do
      if printf '%s' "$out" | grep -q "Error(Contract, #${tolerated})"; then
        echo "    note: already in the intended state (Error(Contract, #${tolerated}))" >&2
        return 0
      fi
    done

    if is_contract_refusal "$out"; then
      echo "error: transaction failed:" >&2
      printf '  %s\n' "$*" >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi

    # The CLI signs before submitting, so its own output tells us whether the
    # transaction may already be live on the network.
    if printf '%s' "$out" | grep -q 'Signing transaction' && [ "$TX_RETRY_AFTER_SIGNING" -ne 1 ]; then
      echo "error: the transaction failed after signing, so it may already have been applied." >&2
      echo "       Refusing to retry blindly; re-run to see the current state." >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi

    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "error: still failing after $attempt attempts:" >&2
      printf '  %s\n' "$*" >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi

    echo "    transient failure, retrying ($attempt/$max_attempts)..." >&2
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
}

# Run a transaction, tolerating the given contract errors as success.
#
# Used where the intent is idempotent: "this member has contributed for round 1"
# is already true if the retry reports AlreadyContributed.
with_tolerance() {
  local codes="$1"
  shift
  TX_OK_ERRORS="$codes"
  stellar_tx "$@"
  local status=$?
  TX_OK_ERRORS=""
  return "$status"
}

# Run a transaction that is inherently idempotent, so it may be retried even
# when the first attempt failed after signing. Creating a trustline that already
# exists is not an error.
tx_idempotent() {
  TX_RETRY_AFTER_SIGNING=1
  stellar_tx "$@"
  local status=$?
  TX_RETRY_AFTER_SIGNING=0
  return "$status"
}

ensure_funded_identity() {
  local name="$1"
  if ! stellar keys address "$name" >/dev/null 2>&1; then
    echo "    creating and funding '$name'" >&2
    stellar keys generate "$name" --network "$NETWORK" --fund >/dev/null
  fi
  stellar keys address "$name"
}

# Read a value from a contract.
#
# The CLI pretty-prints results as JSON, so scalar returns arrive quoted
# (e.g. `"0"`). Strip the quotes and take the last non-empty line. Note this
# deliberately avoids a trailing `grep` that can fail: under `set -e` a
# non-matching grep would abort the script silently.
contract_view() {
  local out
  if ! out=$(stellar contract invoke \
        --source-account "$DEPLOYER" \
        --network "$NETWORK" \
        --send=no \
        "$@" 2>&1); then
    echo "error: view call failed:" >&2
    printf '  %s\n' "$*" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out" | tr -d '"' | grep -v '^[[:space:]]*$' | tail -1
}

token_balance() {
  contract_view --id "$TOKEN_SAC" -- balance --id "$1"
}

# Set to 1 by any failed refusal check, so the run reports honestly at the end.
neg_fail=0

# Assert that a call is refused with one specific contract error.
#
# Simulated only (`--send=no`). A call the contract rejects is refused during
# simulation, so the refusal is observed without submitting a transaction,
# paying a fee, or changing any state. That property is what makes it safe to
# assert refusals in a script whose other steps move real test funds: a check
# that is supposed to fail has nothing to submit.
#
# Three outcomes are told apart, because conflating them produces a misleading
# diagnosis:
#
#   - The contract refused with the expected code  -> pass.
#   - The contract refused with a different code   -> fail, and it is a real
#     finding about the contract.
#   - The call returned no verdict at all (transport failure) -> retried, and if
#     it still cannot be reached, reported as such. This is not a refusal and
#     must never be reported as one: "refused, but not with #13" sends a reader
#     looking for a contract bug that does not exist.
#
# The expected error is matched with its closing parenthesis, so #1 cannot be
# satisfied by #11.
expect_contract_error() {
  local label="$1" expected="$2" source="$3"
  shift 3

  local attempt=1
  local max_attempts=3
  local out
  local code

  while :; do
    set +e
    out=$(stellar contract invoke \
      --source-account "$source" --network "$NETWORK" --send=no "$@" 2>&1)
    code=$?
    set -e

    if [ "$code" -eq 0 ]; then
      printf '    FAIL: %-48s was accepted, expected Error(Contract, #%s)\n' "$label" "$expected"
      neg_fail=1
      return 0
    fi

    # A contract refusal is the only outcome that says anything about the
    # contract. Anything else means the call never got a verdict, so retry.
    if ! is_contract_refusal "$out"; then
      if [ "$attempt" -ge "$max_attempts" ]; then
        printf '    FAIL: %-48s no contract refusal returned after %d attempts\n' \
          "$label" "$attempt"
        printf '%s\n' "$out" | sed -n '1,2p' | sed 's/^/          /'
        neg_fail=1
        return 0
      fi
      echo "    (no verdict on '$label', retrying $attempt/$max_attempts)" >&2
      sleep $((attempt * 3))
      attempt=$((attempt + 1))
      continue
    fi

    if printf '%s' "$out" | grep -q "Error(Contract, #${expected})"; then
      printf '    ok:   %-48s refused with #%s\n' "$label" "$expected"
      return 0
    fi

    printf '    FAIL: %-48s refused, but not with #%s\n' "$label" "$expected"
    printf '%s\n' "$out" | sed -n '1,3p' | sed 's/^/          /'
    neg_fail=1
    return 0
  done
}

echo "==> Ensuring member identities"
# The identity name is needed to sign; the address is needed as a contract
# argument. They are not interchangeable.
MEMBER_NAMES=()
MEMBER_ADDRS=()
for i in $(seq 1 "$MEMBER_COUNT"); do
  member_name="susu-testnet-member$i"
  MEMBER_NAMES+=("$member_name")
  MEMBER_ADDRS+=("$(ensure_funded_identity "$member_name")")
done

# An account that is deliberately not a member, so the contract's refusal of
# outsiders can be asserted. It needs funding only to exist on the ledger.
OUTSIDER_IDENTITY="${SUSU_OUTSIDER_IDENTITY:-susu-testnet-outsider}"
OUTSIDER_ADDR="$(ensure_funded_identity "$OUTSIDER_IDENTITY")"

# ---------------------------------------------------------------------------
# Token: either an externally provided SAC (e.g. Testnet USDC) or a test asset
# that we issue ourselves so the run is fully self-contained.
# ---------------------------------------------------------------------------
MINTED_BY_US=0
if [ -n "${TOKEN_SAC:-}" ]; then
  echo "==> Using externally provided token SAC $TOKEN_SAC"
  echo "    the member accounts must already hold enough of it"
else
  TOKEN_CODE="${SUSU_TEST_TOKEN_CODE:-TSTUSD}"
  ISSUER_IDENTITY="${SUSU_TEST_TOKEN_ISSUER_IDENTITY:-susu-testnet-token-issuer}"
  echo "==> Provisioning test asset $TOKEN_CODE (no testnet USDC faucet is automatable)"

  ISSUER_ADDR="$(ensure_funded_identity "$ISSUER_IDENTITY")"
  ASSET="${TOKEN_CODE}:${ISSUER_ADDR}"

  # The SAC id is a pure function of the asset, so derive it first and deploy
  # only when it is not already on the ledger. This keeps re-runs from failing
  # with a "contract already exists" HostError.
  TOKEN_SAC=$(stellar contract id asset --asset "$ASSET")

  if stellar contract invoke \
        --id "$TOKEN_SAC" --send=no --source-account "$ISSUER_IDENTITY" \
        --network "$NETWORK" --quiet -- decimals >/dev/null 2>&1; then
    echo "    token SAC already deployed: $TOKEN_SAC"
  else
    # NOTE: `stellar contract asset deploy` rejects `--quiet` by exiting 1 with
    # no output at all, so this one command is run without it.
    stellar_tx stellar contract asset deploy \
      --asset "$ASSET" \
      --source-account "$ISSUER_IDENTITY" \
      --network "$NETWORK" >/dev/null
    echo "    token SAC deployed: $TOKEN_SAC"
  fi

  # A classic-asset SAC enforces trustlines. Members need one to hold the asset,
  # and the treasury needs one because `execute_payout` transfers the fee to it:
  # a SAC transfer to an account without a trustline fails, which would make the
  # payout itself fail. Re-running change-trust on an existing line is not an error.
  echo "==> Creating trustlines"
  for i in "${!MEMBER_NAMES[@]}"; do
    tx_idempotent stellar tx new change-trust \
      --line "$ASSET" \
      --source-account "${MEMBER_NAMES[$i]}" \
      --network "$NETWORK" >/dev/null
  done
  TREASURY_IDENTITY="${SUSU_TREASURY_IDENTITY:-susu-testnet-treasury}"
  tx_idempotent stellar tx new change-trust \
    --line "$ASSET" \
    --source-account "$TREASURY_IDENTITY" \
    --network "$NETWORK" >/dev/null

  MINTED_BY_US=1
fi

if [ "$MINTED_BY_US" -eq 1 ]; then
  echo "==> Minting $((INITIAL_MINT / ONE_USDC)) test USD to each member"
  for addr in "${MEMBER_ADDRS[@]}"; do
    stellar_tx stellar contract invoke \
      --id "$TOKEN_SAC" \
      --source-account "$ISSUER_IDENTITY" \
      --network "$NETWORK" \
      -- mint --to "$addr" --amount "$INITIAL_MINT" >/dev/null
  done
  echo "    done"
fi

# ---------------------------------------------------------------------------
# Create the group through the Factory.
# ---------------------------------------------------------------------------
echo "==> Creating group ($MEMBER_COUNT members x 10 USD)"
CREATOR_ADDR=$(stellar keys address "$DEPLOYER")

echo "==> Factory, with the refusals it is expected to make"
expect_contract_error "create a group with a single member" 3 "$DEPLOYER" \
  --id "$FACTORY_ID" -- create_group \
  --creator "$CREATOR_ADDR" --token "$TOKEN_SAC" \
  --contribution_amount "$CONTRIBUTION" --member_capacity 1 --frequency_seconds "$FREQUENCY"
expect_contract_error "create a group with a zero contribution" 2 "$DEPLOYER" \
  --id "$FACTORY_ID" -- create_group \
  --creator "$CREATOR_ADDR" --token "$TOKEN_SAC" \
  --contribution_amount 0 --member_capacity "$CAPACITY" --frequency_seconds "$FREQUENCY"
expect_contract_error "create a group with a zero frequency" 4 "$DEPLOYER" \
  --id "$FACTORY_ID" -- create_group \
  --creator "$CREATOR_ADDR" --token "$TOKEN_SAC" \
  --contribution_amount "$CONTRIBUTION" --member_capacity "$CAPACITY" --frequency_seconds 0

stellar_tx stellar contract invoke \
  --id "$FACTORY_ID" \
  --source-account "$DEPLOYER" \
  --network "$NETWORK" \
  -- create_group \
  --creator "$CREATOR_ADDR" \
  --token "$TOKEN_SAC" \
  --contribution_amount "$CONTRIBUTION" \
  --member_capacity "$CAPACITY" \
  --frequency_seconds "$FREQUENCY" >/dev/null

# Group ids are 1-based and monotonic, so the count is the id we just created.
GROUP_ID=$(contract_view --id "$FACTORY_ID" -- get_group_count)
GROUP_ADDR=$(contract_view --id "$FACTORY_ID" -- get_group --group_id "$GROUP_ID")
echo "    group id:      $GROUP_ID"
echo "    group address: $GROUP_ADDR"

# ---------------------------------------------------------------------------
# Join, start, then snapshot balances before any money moves.
# ---------------------------------------------------------------------------
echo "==> Membership, with the refusals the contract is expected to make"

# The group is Open and empty, which is the only point at which "too early to
# start" and "not active yet" can be observed.
expect_contract_error "start before the group is full" 8 "$DEPLOYER" \
  --id "$GROUP_ADDR" -- start
expect_contract_error "contribute while the group is Open" 9 "${MEMBER_NAMES[0]}" \
  --id "$GROUP_ADDR" -- contribute \
  --member "${MEMBER_ADDRS[0]}" --amount "$CONTRIBUTION" --round 1

echo "    joining ${MEMBER_ADDRS[0]}"
with_tolerance 6 stellar contract invoke \
  --id "$GROUP_ADDR" --source-account "${MEMBER_NAMES[0]}" --network "$NETWORK" \
  -- join --member "${MEMBER_ADDRS[0]}" >/dev/null

expect_contract_error "join twice as the same member" 6 "${MEMBER_NAMES[0]}" \
  --id "$GROUP_ADDR" -- join --member "${MEMBER_ADDRS[0]}"
expect_contract_error "start with one of three members" 8 "$DEPLOYER" \
  --id "$GROUP_ADDR" -- start

for i in 1 2; do
  echo "    joining ${MEMBER_ADDRS[$i]}"
  with_tolerance 6 stellar contract invoke \
    --id "$GROUP_ADDR" --source-account "${MEMBER_NAMES[$i]}" --network "$NETWORK" \
    -- join --member "${MEMBER_ADDRS[$i]}" >/dev/null
done

expect_contract_error "join when the group is full" 7 "$OUTSIDER_IDENTITY" \
  --id "$GROUP_ADDR" -- join --member "$OUTSIDER_ADDR"

echo "==> Starting group"
# Tolerating NotOpen (#5) is safe here: starting moves no funds, and the only
# way this group is no longer Open is that it already started.
with_tolerance 5 stellar contract invoke \
  --id "$GROUP_ADDR" --source-account "$DEPLOYER" --network "$NETWORK" \
  -- start >/dev/null

expect_contract_error "join after the group has started" 5 "$OUTSIDER_IDENTITY" \
  --id "$GROUP_ADDR" -- join --member "$OUTSIDER_ADDR"

echo "==> Snapshotting balances"
BEFORE_MEMBERS=()
for addr in "${MEMBER_ADDRS[@]}"; do
  BEFORE_MEMBERS+=("$(token_balance "$addr")")
done
BEFORE_TREASURY=$(token_balance "$TREASURY_ADDR")

# ---------------------------------------------------------------------------
# Run every round.
# ---------------------------------------------------------------------------
for round in $(seq 1 "$ROUNDS"); do
  echo "==> Round $round: contributing"

  if [ "$round" -eq 1 ]; then
    # Round 1 is the only point at which the group is Active, unfunded, and has
    # a member who has not yet contributed -- which is what makes each of these
    # refusals observable. All simulation-only.
    expect_contract_error "contribute the wrong amount" 12 "${MEMBER_NAMES[0]}" \
      --id "$GROUP_ADDR" -- contribute \
      --member "${MEMBER_ADDRS[0]}" --amount "$((CONTRIBUTION + 1))" --round 1
    expect_contract_error "contribute for the wrong round" 11 "${MEMBER_NAMES[0]}" \
      --id "$GROUP_ADDR" -- contribute \
      --member "${MEMBER_ADDRS[0]}" --amount "$CONTRIBUTION" --round 2
    expect_contract_error "contribute as a non-member" 10 "$OUTSIDER_IDENTITY" \
      --id "$GROUP_ADDR" -- contribute \
      --member "$OUTSIDER_ADDR" --amount "$CONTRIBUTION" --round 1
    expect_contract_error "payout before everyone has contributed" 14 "$DEPLOYER" \
      --id "$GROUP_ADDR" -- execute_payout
  fi

  for i in "${!MEMBER_NAMES[@]}"; do
    # One contribution per member per round: if a retry reports that this member
    # already contributed, the intended end state is already reached.
    with_tolerance 13 stellar contract invoke \
      --id "$GROUP_ADDR" --source-account "${MEMBER_NAMES[$i]}" --network "$NETWORK" \
      -- contribute --member "${MEMBER_ADDRS[$i]}" --amount "$CONTRIBUTION" --round "$round" >/dev/null

    if [ "$round" -eq 1 ] && [ "$i" -eq 0 ]; then
      # One contribution per member per round is the invariant that keeps the
      # payout order meaningful. The contribution just made is real; the refusal
      # of a second one is simulated.
      expect_contract_error "contribute twice in the same round" 13 "${MEMBER_NAMES[0]}" \
        --id "$GROUP_ADDR" -- contribute \
        --member "${MEMBER_ADDRS[0]}" --amount "$CONTRIBUTION" --round 1
    fi
  done

  echo "==> Round $round: paying out"
  # Paying out a round that is already paid is the same desired end state.
  with_tolerance 15 stellar contract invoke \
    --id "$GROUP_ADDR" --source-account "$DEPLOYER" --network "$NETWORK" \
    -- execute_payout >/dev/null
done

echo "==> Refusals once the group has completed"
expect_contract_error "contribute to a completed group" 17 "${MEMBER_NAMES[0]}" \
  --id "$GROUP_ADDR" -- contribute \
  --member "${MEMBER_ADDRS[0]}" --amount "$CONTRIBUTION" --round "$ROUNDS"
expect_contract_error "payout a completed group" 17 "$DEPLOYER" \
  --id "$GROUP_ADDR" -- execute_payout

# ---------------------------------------------------------------------------
# Assert the financial invariants against real on-chain balances.
#
# Deltas, not absolutes, so repeated runs assert the same thing.
# ---------------------------------------------------------------------------
echo "==> Asserting balance changes"

fail=0
check() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    printf '    ok:   %-36s %s\n' "$label" "$actual"
  else
    printf '    FAIL: %-36s got %s, expected %s\n' "$label" "$actual" "$expected"
    fail=1
  fi
}

for i in "${!MEMBER_ADDRS[@]}"; do
  after=$(token_balance "${MEMBER_ADDRS[$i]}")
  check "member$((i + 1)) net change (-0.15)" "$((after - BEFORE_MEMBERS[i]))" "$EXPECTED_MEMBER_DELTA"
done
check "treasury net change (+0.45)" \
  "$(( $(token_balance "$TREASURY_ADDR") - BEFORE_TREASURY ))" "$EXPECTED_TREASURY_DELTA"
check "group retains nothing" "$(token_balance "$GROUP_ADDR")" "0"

STATUS=$(contract_view --id "$GROUP_ADDR" -- get_status)
if printf '%s' "$STATUS" | grep -q 'Completed'; then
  printf '    ok:   %-36s %s\n' "final status" "$STATUS"
else
  printf '    FAIL: %-36s %s\n' "final status" "$STATUS"
  fail=1
fi

echo
if [ "$fail" -ne 0 ] || [ "$neg_fail" -ne 0 ]; then
  echo "E2E FAILED" >&2
  exit 1
fi
echo "E2E PASSED: $ROUNDS rounds, $MEMBER_COUNT members x 10 USD"
echo "  each member paid 30 and received 29.85 -> net -0.15 USD"
echo "  treasury received 3 x 0.15 = 0.45 USD"
echo "  group retained 0"
echo "  every expected refusal was refused with the right contract error"
echo "Group: $GROUP_ADDR"
echo "Token: $TOKEN_SAC"
