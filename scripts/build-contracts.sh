#!/usr/bin/env bash
#
# Build the Susu contracts to Wasm for the on-chain target.
#
# This is the build the deployment integration test depends on: the test loads
# `target/wasm32v1-none/release/susu_group.wasm` via `include_bytes!`, so the
# Wasm must exist before `cargo test -p susu-factory --features wasm-integration`
# is run.
#
# Equivalent to `stellar contract build`, without requiring the Stellar CLI.

set -euo pipefail

# Always build into this repository's `target/`, regardless of what the caller
# has CARGO_TARGET_DIR set to. The integration test resolves the Wasm by a path
# relative to the crate, so a redirected target dir would break it.
cd "$(dirname "$0")/.."
export CARGO_TARGET_DIR="$PWD/target"

TARGET=wasm32v1-none

if ! rustup target list --installed | grep -qx "$TARGET"; then
  echo "error: Rust target '$TARGET' is not installed." >&2
  echo "       Install it with: rustup target add $TARGET" >&2
  exit 1
fi

echo "Building contracts for $TARGET (release)..."
cargo build --workspace --target "$TARGET" --release "$@"

echo
echo "Wasm artifacts:"
ls -la "target/$TARGET/release/"*.wasm
