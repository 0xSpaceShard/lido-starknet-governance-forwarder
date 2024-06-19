// StarkNet contract module for BridgeExecutor


#[starknet::interface]
pub trait IMockDelegate<TStorage> {
    fn get_counter(self: @TStorage) -> u256;
    fn increase_counter(ref self: TStorage, increase_amount: u256) -> u256;
}


#[starknet::contract]
pub mod MockDelegate {

    // Importing required modules and types from the starknet crate and other dependencies
    use starknet::{ContractAddress, EthAddress, get_block_timestamp, ClassHash, get_caller_address, get_contract_address, SyscallResultTrait, syscalls::{
        call_contract_syscall, library_call_syscall,
    }};

    use super::IMockDelegate;

    #[storage]
    struct Storage {
        counter: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        
    }
    
    #[constructor]
    fn constructor(ref self: ContractState) {
    }

    #[abi(embed_v0)]
    impl MockDelegateImpl of IMockDelegate<ContractState> {

        fn get_counter(self: @ContractState) -> u256 {
            self.counter.read()
        }

        fn increase_counter(ref self: ContractState, increase_amount: u256) -> u256 {
            let current_counter = self.counter.read();
            let new_counter = current_counter + increase_amount;
            self.counter.write(new_counter);
            new_counter
        }
    }
}
