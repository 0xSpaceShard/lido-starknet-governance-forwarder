use starknet::{ContractAddress, EthAddress};
use starknet::account::{Call};


#[derive(Drop, Copy, Serde, Debug, PartialEq)]
pub struct CallOrDelegateCall {
    pub to: felt252,
    pub selector: felt252,
    pub calldata: Span<felt252>
}


#[derive(Drop, Copy, Serde, Debug, PartialEq)]
pub struct ActionSet {
    pub calls: Span<CallOrDelegateCall>,
    pub with_delegate_calls: Span<bool>,
    pub execution_time: u64,
    pub executed: bool,
    pub canceled: bool
}

#[derive(Drop, Copy, Serde, Debug, PartialEq)]
pub enum ActionSetState {
    Queued,
    Executed,
    Canceled,
    Expired
}

#[starknet::interface]
pub trait IBridgeExecutor<TStorage> {

    // GETTERS
    fn get_ethereum_governance_executor(self: @TStorage) -> EthAddress;
    fn get_delay(self: @TStorage) -> u64;
    fn get_grace_period(self: @TStorage) -> u64;
    fn get_minimum_delay(self: @TStorage) -> u64;
    fn get_maximum_delay(self: @TStorage) -> u64;
    fn get_guardian(self: @TStorage) -> ContractAddress;
    fn get_actions_set_count(self: @TStorage) -> u32;
    fn get_actions_set_by_id(self: @TStorage, action_set_id: u32) -> ActionSet;
    fn get_current_state(self: @TStorage, action_set_id: u32) -> ActionSetState;
    fn is_action_queued(self: @TStorage, action_hash: u256) -> bool;


    // SETTERS
    fn update_guardian(ref self: TStorage, guardian: ContractAddress);
    fn update_delay(ref self: TStorage, delay: u64);
    fn update_grace_period(ref self: TStorage, grace_period: u64);
    fn update_minimum_delay(ref self: TStorage, minimum_delay: u64);
    fn update_maximum_delay(ref self: TStorage, maximum_delay: u64);
    fn update_ethereum_governance_executor(ref self: TStorage, ethereum_governance_executor: EthAddress);

    // LOGIC
    fn execute(ref self: TStorage, actions_set_id: u32);
    fn cancel(ref self: TStorage, actions_set_id: u32); 
}

