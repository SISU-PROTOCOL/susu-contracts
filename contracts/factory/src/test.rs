#![cfg(test)]

use super::*;
use soroban_sdk::Env;

#[test]
fn version_is_reported() {
    let env = Env::default();
    let contract_id = env.register(FactoryContract, ());
    let client = FactoryContractClient::new(&env, &contract_id);

    assert_eq!(client.version(), CONTRACT_VERSION);
}
