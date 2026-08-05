# Contributing to Susu Protocol Contracts

Thanks for your interest. This repository governs on-chain financial logic, so the review
bar is deliberately high.

## Before you start

- Read `README.md` and `docs/CONTRACT_SPEC.md`.
- Read `SECURITY.md` — it lists the invariants you must not break.
- For anything touching fees, custody, authorization, payout behavior, or recipient
  selection, open an issue **first** and wait for maintainer direction. Do not open a PR
  that changes financial semantics on its own.

## Ground rules

1. **Never** use floating-point arithmetic for money. Integer math only.
2. **Never** add arbitrary withdrawal functionality for a creator, admin, backend, or
   treasury.
3. **Never** move financial authority off-chain.
4. **Never** commit secrets, private keys, or seed phrases.
5. Keep the code simple and auditable. Prefer explicitness over cleverness.
6. Every behavior change needs tests, including negative paths.

## Development setup

```bash
rustup target add wasm32v1-none
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
stellar contract build
```

## Testing requirements

Contract PRs must include tests for:

- The happy path.
- All negative paths: wrong token, wrong amount, wrong member, wrong round, unauthorized
  caller, duplicate contribution, duplicate payout, early payout, wrong recipient.
- Boundary values and invalid configuration.
- The final round completing exactly once.
- Storage key/TTL behavior where relevant.

## Commit messages

Use clear, imperative subject lines. Reference issues where applicable. Do not add
co-author trailers for tooling.

## Pull requests

- Fill in the PR template, including the security and invariant impact sections.
- Keep PRs focused — one concern per PR.
- CI must be green: format, clippy, tests, wasm build, `cargo deny`, `cargo audit`.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
