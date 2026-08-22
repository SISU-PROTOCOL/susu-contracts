#!/usr/bin/env bash
#
# Deploy the Susu contracts to Stellar Testnet.
#
# Testnet only. Mainnet deployment is manual, requires the readiness gate to be
# passed and explicit human approval, and is deliberately not supported here.
#
# This script is idempotent and safe to re-run: identities are created only when
# missing, and the Factory is deployed with its `__constructor` so it is never
# observable in an uninitialized state.
#
# Usage:
#   ./scripts/deploy-testnet.sh
#
# Optional environment overrides (see .env.example):
#   SUSU_DEPLOYER_IDENTITY (default: susu-testnet-deployer)
#   SUSU_ADMIN_IDENTITY    (default: susu-testnet-admin)
#   SUSU_TREASURY_IDENTITY (default: susu-testnet-treasury)
#   PROTOCOL_FEE_BPS       (default: 50)
#   STELLAR_NETWORK        (default: testnet)

set -euo pipefail

cd "$(dirname "$0")/.."

NETWORK="${STELLAR_NETWORK:-testnet}"
if [ "$NETWORK" != "testnet" ]; then
  echo "error: this script only deploys to testnet (got STELLAR_NETWORK=$NETWORK)." >&2
  exit 1
fi

DEPLOYER="${SUSU_DEPLOYER_IDENTITY:-susu-testnet-deployer}"
ADMIN="${SUSU_ADMIN_IDENTITY:-susu-testnet-admin}"
TREASURY="${SUSU_TREASURY_IDENTITY:-susu-testnet-treasury}"
FEE_BPS="${PROTOCOL_FEE_BPS:-50}"

if [ "$FEE_BPS" -ne 50 ]; then
  echo "warning: PROTOCOL_FEE_BPS=$FEE_BPS, but the protocol invariant is 50 (0.50%)." >&2
fi

command -v stellar >/dev/null 2>&1 || {
  echo "error: the Stellar CLI is not installed." >&2
  exit 1
}

# Run a stellar transaction, surfacing the full output if it fails.
#
# `--quiet` is deliberately not used for transactions: it also swallows error
# messages, so a real failure (a rejected simulation, a HostError) becomes a
# silent `exit 1` with no explanation.
stellar_tx() {
  local out
  if ! out=$("$@" 2>&1); then
    echo "error: command failed:" >&2
    printf '  %s\n' "$*" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# Identities. Private keys stay in the Stellar CLI key store, never in this
# repository and never in an environment file.
# ---------------------------------------------------------------------------
ensure_identity() {
  local name="$1"
  if stellar keys address "$name" >/dev/null 2>&1; then
    echo "identity '$name' already exists"
  else
    echo "creating and funding identity '$name'"
    stellar keys generate "$name" --network "$NETWORK" --fund >/dev/null
  fi
  stellar keys address "$name"
}

echo "==> Ensuring identities"
ensure_identity "$DEPLOYER" >/dev/null
ensure_identity "$ADMIN" >/dev/null
ensure_identity "$TREASURY" >/dev/null

DEPLOYER_ADDR=$(stellar keys address "$DEPLOYER")
ADMIN_ADDR=$(stellar keys address "$ADMIN")
TREASURY_ADDR=$(stellar keys address "$TREASURY")

if [ "$DEPLOYER_ADDR" = "$ADMIN_ADDR" ] || [ "$DEPLOYER_ADDR" = "$TREASURY_ADDR" ] || [ "$ADMIN_ADDR" = "$TREASURY_ADDR" ]; then
  echo "error: deployer, admin and treasury must be distinct identities." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "==> Building contracts"
./scripts/build-contracts.sh >/dev/null

GROUP_WASM="target/wasm32v1-none/release/susu_group.wasm"
FACTORY_WASM="target/wasm32v1-none/release/susu_factory.wasm"

# ---------------------------------------------------------------------------
# Upload the Group implementation, then deploy the Factory pointing at it.
# ---------------------------------------------------------------------------
echo "==> Uploading Group wasm"
UPLOAD_OUT=$(stellar_tx stellar contract upload \
  --wasm "$GROUP_WASM" \
  --source-account "$DEPLOYER" \
  --network "$NETWORK")
GROUP_WASM_HASH=$(printf '%s\n' "$UPLOAD_OUT" | grep -oE '^[0-9a-f]{64}$' | tail -1)

if [ -z "$GROUP_WASM_HASH" ]; then
  echo "error: could not parse a wasm hash from the upload output." >&2
  printf '%s\n' "$UPLOAD_OUT" >&2
  exit 1
fi
echo "    group wasm hash: $GROUP_WASM_HASH"

echo "==> Deploying Factory"
DEPLOY_OUT=$(stellar_tx stellar contract deploy \
  --wasm "$FACTORY_WASM" \
  --source-account "$DEPLOYER" \
  --network "$NETWORK" \
  -- \
  --admin "$ADMIN_ADDR" \
  --group_wasm_hash "$GROUP_WASM_HASH" \
  --treasury "$TREASURY_ADDR" \
  --fee_bps "$FEE_BPS")
FACTORY_ID=$(printf '%s\n' "$DEPLOY_OUT" | grep -oE '^C[A-Z0-9]{55}$' | tail -1)

if [ -z "$FACTORY_ID" ]; then
  echo "error: could not parse a contract id from the deploy output." >&2
  printf '%s\n' "$DEPLOY_OUT" >&2
  exit 1
fi
echo "    factory id:      $FACTORY_ID"

# ---------------------------------------------------------------------------
# Verify what we just deployed, by reading it back from the chain. The Factory
# is constructed at deploy time, so there is never an uninitialized window.
# ---------------------------------------------------------------------------
echo "==> Verifying deployment on-chain"
CONFIG=$(stellar contract invoke \
  --id "$FACTORY_ID" \
  --source-account "$DEPLOYER" \
  --network "$NETWORK" \
  --quiet \
  -- get_config)

verify_contains() {
  if ! printf '%s' "$CONFIG" | grep -qF "$2"; then
    echo "error: get_config() did not contain expected $1: '$2'" >&2
    echo "       got: $CONFIG" >&2
    exit 1
  fi
  echo "    ok: $1"
}

verify_contains "admin" "$ADMIN_ADDR"
verify_contains "treasury" "$TREASURY_ADDR"
verify_contains "group wasm hash" "$GROUP_WASM_HASH"
verify_contains "fee_bps = 50" "50"

GROUP_COUNT=$(stellar contract invoke \
  --id "$FACTORY_ID" \
  --source-account "$DEPLOYER" \
  --network "$NETWORK" \
  --quiet \
  -- get_group_count)
if [ "$GROUP_COUNT" != "0" ]; then
  echo "error: fresh Factory reports $GROUP_COUNT groups, expected 0" >&2
  exit 1
fi
echo "    ok: group count starts at 0"

echo
echo "=================== Testnet deployment ==================="
printf 'network            %s\n' "$NETWORK"
printf 'deployer           %s\n' "$DEPLOYER_ADDR"
printf 'admin              %s\n' "$ADMIN_ADDR"
printf 'treasury           %s\n' "$TREASURY_ADDR"
printf 'fee_bps            %s\n' "$FEE_BPS"
printf 'group wasm hash    %s\n' "$GROUP_WASM_HASH"
printf 'factory contract   %s\n' "$FACTORY_ID"
echo "=========================================================="
echo
echo "Explorer: https://stellar.expert/explorer/testnet/contract/$FACTORY_ID"

# ---------------------------------------------------------------------------
# Record the public addresses for the other repositories and for the docs.
# `.env.testnet` is gitignored (.env.*); addresses are public, keys are not.
# ---------------------------------------------------------------------------
cat > .env.testnet <<EOF
# Generated by scripts/deploy-testnet.sh. Gitignored. Public addresses only.
STELLAR_NETWORK=$NETWORK
STELLAR_RPC_URL=https://soroban-testnet.stellar.org
STELLAR_NETWORK_PASSPHRASE="Test SDF Network ; September 2015"

SUSU_DEPLOYER_PUBLIC=$DEPLOYER_ADDR
SUSU_ADMIN_PUBLIC=$ADMIN_ADDR
SUSU_TREASURY_PUBLIC=$TREASURY_ADDR

STELLAR_TESTNET_USDC_SAC=CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA
STELLAR_TESTNET_USDC_ISSUER=GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5

PROTOCOL_FEE_BPS=$FEE_BPS

FACTORY_CONTRACT_ID=$FACTORY_ID
GROUP_WASM_HASH=$GROUP_WASM_HASH
EOF
echo "Wrote .env.testnet"
