//! # Susu Protocol — Group Contract
//!
//! One Group contract instance per Susu group. This contract is the **financial
//! authority** for its group's pool.
//!
//! ## Financial invariants (implemented in Phase 1)
//! ```text
//! fee              = amount * fee_bps / 10_000
//! recipient_amount = amount - fee
//! fee_bps          = 50  (0.50%)
//! fee + recipient_amount == pool
//! ```
//! Integer arithmetic only. Floating point is forbidden anywhere in money math.
//!
//! - One contribution per member per round.
//! - One payout per round.
//! - Configured token only, exact configured amount, no early payout.
//! - Recipient comes from the immutable payout order.
//! - No arbitrary withdrawal, by anyone, ever.
//! - Final round completes exactly once.
//!
//! ## Status: Phase 0 skeleton
//! This crate is scaffolding only. The full Group interface is implemented in
//! **Phase 1** and must match `docs/CONTRACT_SPEC.md`:
//!
//! ```text
//! initialize(...)   join(member)          start()
//! contribute(member, amount, round)       execute_payout()
//! get_group()       get_member(address)   get_round(round)
//! get_current_recipient()                 get_current_round()
//! get_pool_balance()                      is_contribution_complete()
//! get_status()
//! ```
//!
//! No financial logic may be added here without human review (see `SECURITY.md`).

#![no_std]

use soroban_sdk::{contract, contractimpl, Env};

/// Contract version reported by `version()`. Bumped with each released interface.
const CONTRACT_VERSION: u32 = 1;

/// The Susu Group contract type.
#[contract]
pub struct GroupContract;

#[contractimpl]
impl GroupContract {
    /// Returns the ABI/interface version of this contract.
    ///
    /// Metadata only — carries no financial meaning.
    pub fn version(_env: Env) -> u32 {
        CONTRACT_VERSION
    }
}

mod test;
