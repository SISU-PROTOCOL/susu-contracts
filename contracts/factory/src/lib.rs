//! # Susu Protocol — Factory Contract
//!
//! The Factory creates and registers one dedicated **Group** contract per Susu group.
//!
//! ## Authority
//! The Factory is **not** a custodian. It never holds group funds and can never move
//! member money. All financial authority lives in the individual Group contracts.
//!
//! ## Status: Phase 0 skeleton
//! This crate is scaffolding only. The interface below is intentionally minimal so the
//! workspace builds and CI is green. The full Factory interface is implemented in
//! **Phase 1** and must match `docs/CONTRACT_SPEC.md`:
//!
//! ```text
//! initialize(admin, group_wasm_hash, treasury, fee_bps)
//! create_group(...)
//! get_group(...)
//! get_group_count()
//! set_fee(...)
//! set_treasury(...)
//! pause()
//! unpause()
//! ```
//!
//! No financial logic may be added here without human review (see `SECURITY.md`).

#![no_std]

use soroban_sdk::{contract, contractimpl, Env};

/// Contract version reported by `version()`. Bumped with each released interface.
const CONTRACT_VERSION: u32 = 1;

/// The Susu Factory contract type.
#[contract]
pub struct FactoryContract;

#[contractimpl]
impl FactoryContract {
    /// Returns the ABI/interface version of this contract.
    ///
    /// Metadata only — carries no financial meaning.
    pub fn version(_env: Env) -> u32 {
        CONTRACT_VERSION
    }
}

mod test;
