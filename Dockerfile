# Reproducible build-and-test image for susu-contracts.
#
# The point of this image is reproducible verification of the exact artifact:
# the same commands CI runs, on a pinned toolchain, on a machine that has no Rust
# installed at all. It therefore does not "deploy" anything and it needs no
# Stellar credentials — it builds and tests the contracts.
#
# Everything is pinned to what CI uses, because a verification image that
# verifies a different toolchain is worse than none:
#
#   * Rust 1.96.0 — the channel in rust-toolchain.toml and the `toolchain:` value
#     in the `contracts` job of .github/workflows/ci.yml.
#   * rustfmt + clippy — CI installs both, and both are used below.
#   * wasm32v1-none — `./scripts/build-contracts.sh` refuses to run without it,
#     and the wasm-integration test loads the Wasm it produces.
#
# The Stellar CLI is deliberately NOT installed. `scripts/build-contracts.sh`
# documents itself as the equivalent of `stellar contract build` using a plain
# `cargo build --target wasm32v1-none --release`, and CI never installs the CLI
# either, so requiring it here would pin a tool this repository does not use.
#
# No secret is ever baked in. `.dockerignore` keeps `.env`, `.env.*`, `target/`
# and `.git/` out of the build context, so `COPY . .` cannot pick up credentials
# and the image is reproducible from source alone.
#
#   Build and verify:  docker build -t susu-contracts .
#   Run the build script again (cached, prints the artifact paths):
#                      docker run --rm susu-contracts
#   Inspect the Wasm:  docker run --rm susu-contracts ls -la target/wasm32v1-none/release

# The base is the full `rust` image rather than `-slim` on purpose: the contract
# tests compile and link host binaries, which needs a C linker (`cc`), and the
# slim variant ships none. That costs OS packages, so a base-image CVE scan will
# report findings, and they are accepted knowingly rather than ignored: this
# image is built to verify an artifact and then thrown away, it runs no untrusted
# input, and it is never deployed anywhere. If that ever changes — if this image
# starts being published or run as a service — pin the base by digest and move to
# a distroless runtime stage.
FROM rust:1.96.0-bookworm AS toolchain

# Installed explicitly rather than left to rust-toolchain.toml, so the image
# build fails loudly if a component or target cannot be resolved instead of
# silently fetching one at first use.
RUN rustup component add rustfmt clippy \
 && rustup target add wasm32v1-none

WORKDIR /src

# --- source ------------------------------------------------------------------
FROM toolchain AS source

# The whole tree, minus what `.dockerignore` excludes. The dependency download is
# kept in its own layer; the source arrives first because `cargo fetch` has to
# resolve the workspace, which needs each crate's target sources to be present.
COPY . .
RUN cargo fetch --locked

# --- verification ------------------------------------------------------------
FROM source AS verified

# The same sequence as the `contracts` job in .github/workflows/ci.yml, run at
# image build time so a failing check fails the build and surfaces in its exit
# code. `cargo fetch --locked` above means this resolves no new versions: if
# Cargo.lock and the manifests disagree, the build fails instead of drifting.
#
# This is the whole value of the image — `docker build` is the verification.
RUN cargo fmt --all --check \
 && cargo clippy --workspace --all-targets -- -D warnings \
 && cargo test --workspace \
 && ./scripts/build-contracts.sh \
 && cargo test -p susu-factory --features wasm-integration

# Re-running the container replays the repository's own build, which is the
# script a maintainer would otherwise have to install a toolchain to run. The
# Wasm left by the layer above makes it quick, and the artifacts stay on disk for
# inspection or extraction via `docker cp`.
CMD ["./scripts/build-contracts.sh"]
