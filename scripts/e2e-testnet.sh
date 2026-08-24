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

# Run a transaction, surfacing the full output if it fails.
#
# `--quiet` is deliberately not used for transactions: it also swallows error
# messages, so a real failure (a rejected simulation, a HostError) becomes a
# silent `exit 1` with no explanation.
stellar_tx() {
  local out
  if ! out=$("$@" 2>&1); then
    echo "error: transaction failed:" >&2
    printf '  %s\n' "$*" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
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
    stellar_tx stellar tx new change-trust \
      --line "$ASSET" \
      --source-account "${MEMBER_NAMES[$i]}" \
      --network "$NETWORK" >/dev/null
  done
  TREASURY_IDENTITY="${SUSU_TREASURY_IDENTITY:-susu-testnet-treasury}"
  stellar_tx stellar tx new change-trust \
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
echo "==> Joining members"
for i in "${!MEMBER_NAMES[@]}"; do
  stellar_tx stellar contract invoke \
    --id "$GROUP_ADDR" --source-account "${MEMBER_NAMES[$i]}" --network "$NETWORK" \
    -- join --member "${MEMBER_ADDRS[$i]}" >/dev/null
  echo "    joined ${MEMBER_ADDRS[$i]}"
done

echo "==> Starting group"
stellar_tx stellar contract invoke \
  --id "$GROUP_ADDR" --source-account "$DEPLOYER" --network "$NETWORK" \
  -- start >/dev/null

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
  for i in "${!MEMBER_NAMES[@]}"; do
    stellar_tx stellar contract invoke \
      --id "$GROUP_ADDR" --source-account "${MEMBER_NAMES[$i]}" --network "$NETWORK" \
      -- contribute --member "${MEMBER_ADDRS[$i]}" --amount "$CONTRIBUTION" --round "$round" >/dev/null
  done
  echo "==> Round $round: paying out"
  stellar_tx stellar contract invoke \
    --id "$GROUP_ADDR" --source-account "$DEPLOYER" --network "$NETWORK" \
    -- execute_payout >/dev/null
done

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
if [ "$fail" -ne 0 ]; then
  echo "E2E FAILED" >&2
  exit 1
fi
echo "E2E PASSED: $ROUNDS rounds, $MEMBER_COUNT members x 10 USD"
echo "  each member paid 30 and received 29.85 -> net -0.15 USD"
echo "  treasury received 3 x 0.15 = 0.45 USD"
echo "  group retained 0"
echo "Group: $GROUP_ADDR"
echo "Token: $TOKEN_SAC"
