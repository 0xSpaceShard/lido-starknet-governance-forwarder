
mod testBridgeExecutor {
    // Importing required modules and types from the starknet crate and other dependencies
    use starknet::{ContractAddress, EthAddress, get_block_timestamp, ClassHash, get_caller_address, get_contract_address, SyscallResultTrait, syscalls::{
        call_contract_syscall, library_call_syscall,
    }};
    use lido_forward::bridge_executor::interface::{ActionSet, ActionSetState, IBridgeExecutorDispatcher, IBridgeExecutorDispatcherTrait, CallOrDelegateCall}; 
    use lido_forward::bridge_executor::bridge_executor::BridgeExecutor; 
    use lido_forward::mock_delegate::mock_delegate::{MockDelegate, IMockDelegateDispatcher, IMockDelegateDispatcherTrait};
    use core::integer::{u128_byte_reverse, BoundedInt}; 
    use snforge_std::{ declare, ContractClassTrait, cheat_caller_address, CheatSpan, L1HandlerTrait, spy_events, SpyOn, EventSpy, EventAssertions, store, load, map_entry_address, cheat_block_timestamp };

    mod TestConstants {
        pub const GUARDIAN: felt252 = 2000;
        pub const ETHEREUM_GOVERNANCE_EXECUTOR: felt252 = 3000;
        pub const DELAY: u64 = 50;
        pub const MINIMUM_DELAY: u64 = 2;
        pub const MAXIMUM_DELAY: u64 = 200;
        pub const GRACE_PERIOD: u64 = 1000;
        pub const SELECTOR: felt252 = 0x010e13e50cb99b6b3c8270ec6e16acfccbe1164a629d74b43549567a77593aff;
        pub const UPD_DELAY_SELECTOR: felt252 = 0x0000329c2e80b0ddda3f2a8b0f9413c126650f2939e4508c5b0dccc470f6b7b4;
        pub const INCR_COUNTER_SELECTOR: felt252 = 0x0245f9bea6574169db91599999bf914dd43aebc1e0544bdc96c9f401a52b8768;
    }

    fn setup() -> IBridgeExecutorDispatcher {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        calldata.append(TestConstants::DELAY.into());
        calldata.append(TestConstants::GRACE_PERIOD.into());
        calldata.append(TestConstants::MINIMUM_DELAY.into());
        calldata.append(TestConstants::MAXIMUM_DELAY.into());
        calldata.append(TestConstants::GUARDIAN);
        calldata.append(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR);
        let contract = declare("BridgeExecutor").unwrap();
        let (contract_address, _) = contract.deploy(@calldata).unwrap();
        IBridgeExecutorDispatcher { contract_address: contract_address }
    }


    fn setup_mock() -> (IMockDelegateDispatcher, felt252) {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        let contract = declare("MockDelegate").unwrap();
        let (contract_address, _) = contract.deploy(@calldata).unwrap();
        (IMockDelegateDispatcher { contract_address: contract_address}, contract.class_hash.into())
    }

    fn _felt_to_bool(felt_to_convert: felt252) -> bool {
        if felt_to_convert == 0 {
            false
        } else if felt_to_convert == 1 {
            true
        } else {
            panic!("NOT_BOOL"); // Ensures strict boolean inputs.
            true
        }
    }

    fn _reverse_endianness(value: u256) -> u256 {
        let new_low = u128_byte_reverse(value.high); // Reverse the byte order of the high part.
        let new_high = u128_byte_reverse(value.low); // Reverse the byte order of the low part.
        u256 { low: new_low, high: new_high } // Reconstructs the u256 with swapped parts.
    }

    fn _get_action_hash(with_delegate_calls: felt252, to: felt252, selector: felt252, calldata: Span<felt252>, execution_time: u64) -> u256 {
        let mut hash_array = ArrayTrait::<u256>::new();
        hash_array.append(execution_time.into());
        hash_array.append(with_delegate_calls.into());
        hash_array.append(to.into());
        hash_array.append(selector.into());
        let mut index_calldata = 0;
        while index_calldata != calldata.len() {
            hash_array.append((*calldata.at(index_calldata)).into());
            index_calldata += 1;
        };
        let hash = keccak::keccak_u256s_be_inputs(hash_array.span());
        _reverse_endianness(hash) 
    }



    fn build_set_action_from_calldata(data: Span<felt252>, execution_time: u64) -> (ActionSet, Array<u256>) {
        let call_len: u32 = (*data.at(1)).try_into().unwrap();
        let mut hash_array = ArrayTrait::<u256>::new();
        let mut with_delegate_calls = ArrayTrait::<bool>::new();
        let mut calls = ArrayTrait::<CallOrDelegateCall>::new();
        let mut index_action: u32 = 0;
        let mut current_index: u32 = 2; 

        while index_action != call_len {
            let elem_with_delegate_calls: felt252 = *data.at(current_index); 
            let elem_with_delegate_calls_bool = _felt_to_bool(elem_with_delegate_calls);
            with_delegate_calls.append(elem_with_delegate_calls_bool);

            let elem_to = *data.at(current_index + 1);
            let elem_selector = *data.at(current_index + 2);

            let elem_calldata_len: u32 = (*data.at(current_index + 3)).try_into().unwrap();
            let mut index_calldata = 0;
            let mut elem_calldata = ArrayTrait::<felt252>::new();

            while index_calldata != elem_calldata_len {
                let elem_elem_calldata = *data.at(current_index + index_calldata + 4);
                elem_calldata.append(elem_elem_calldata);
                index_calldata += 1;
            };

            let elem_calldata_span = elem_calldata.span();
            let current_action_hash = _get_action_hash(elem_with_delegate_calls, elem_to, elem_selector, elem_calldata_span, execution_time);
            hash_array.append(current_action_hash);
            let elem_call : CallOrDelegateCall = CallOrDelegateCall {
                to: elem_to,
                selector: elem_selector,
                calldata: elem_calldata_span
            };
            calls.append(elem_call);
            current_index += 4 + elem_calldata_len; 
            index_action += 1;
        };
        (ActionSet {
            calls: calls.span(),
            with_delegate_calls: with_delegate_calls.span(),
            execution_time: execution_time,
            executed: false,
            canceled: false,
        }, hash_array)
    }
    
    

    fn between_u64(min: u64, max: u64, val: u64) -> u64 {
        assert(max > min, 'min gte max');
        min + (val % (max - min + 1))
    }

    #[test]
    fn test_deploy() {
        let _bridge_executor = setup();
    }

    // setters

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_ethereum_governance_executor_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_ethereum_governance_executor(3001.try_into().unwrap());
    }

    #[test]
    fn test_update_ethereum_governance_executor() {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        bridge_executor.update_ethereum_governance_executor(3001.try_into().unwrap());
        let ethereum_governance_executor = bridge_executor.get_ethereum_governance_executor();
        assert(ethereum_governance_executor == 3001.try_into().unwrap(), 'invalid e_g_e')
    }

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_guardian_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_guardian(2001.try_into().unwrap());
    }

    #[test]
    fn test_update_guardian() {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        bridge_executor.update_guardian(2001.try_into().unwrap());
        let guardian = bridge_executor.get_guardian();
        assert(guardian == 2001.try_into().unwrap(), 'invalid g')
    }

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_grace_period_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_grace_period(1001.try_into().unwrap());
    }

    #[test]
    #[should_panic(expected: ('Grace period too short',))]
    fn test_update_grace_period_grace_period_too_short(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_grace_period = between_u64(0, BridgeExecutor::Constants::MINIMUM_GRACE_PERIOD - 1, a);
        bridge_executor.update_grace_period(new_grace_period);
    }

    #[test]
    fn test_update_grace_period_grace_period(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_grace_period = between_u64(BridgeExecutor::Constants::MINIMUM_GRACE_PERIOD, BoundedInt::max(), a);
        bridge_executor.update_grace_period(new_grace_period);
        let grace_period = bridge_executor.get_grace_period();
        assert(grace_period == new_grace_period, 'invalid gp')
    }

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_minimum_delay_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_minimum_delay(2);
    }

    #[test]
    #[should_panic(expected: ('Minimum delay too long',))]
    fn test_update_minimum_delay_too_long(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_minimum_delay = between_u64(TestConstants::MAXIMUM_DELAY , BoundedInt::max(), a);
        bridge_executor.update_minimum_delay(new_minimum_delay);
    }

    #[test]
    fn test_update_minimum_delay(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_minimum_delay = between_u64(0, TestConstants::MAXIMUM_DELAY - 1, a);
        bridge_executor.update_minimum_delay(new_minimum_delay);
        let minimum_delay = bridge_executor.get_minimum_delay();
        assert(minimum_delay == new_minimum_delay, 'invalid md')
    }

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_maximum_delay_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_maximum_delay(2);
    }

    #[test]
    #[should_panic(expected: ('Maximum delay too short',))]
    fn test_update_maximum_delay_too_long(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_maximum_delay = between_u64(0, TestConstants::MINIMUM_DELAY, a);
        bridge_executor.update_maximum_delay(new_maximum_delay);
    }

    #[test]
    fn test_update_maximum_delay(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_maximum_delay = between_u64(TestConstants::MINIMUM_DELAY + 1, BoundedInt::max(), a);
        bridge_executor.update_maximum_delay(new_maximum_delay);
        let maximum_delay = bridge_executor.get_maximum_delay();
        assert(maximum_delay == new_maximum_delay, 'invalid md')
    }

    #[test]
    #[should_panic(expected: ('Only callable by this',))]
    fn test_update_delay_only_this() {
        let bridge_executor = setup();
        bridge_executor.update_delay(2);
    }

    #[test]
    #[should_panic(expected: ('Delay shorter than min',))]
    fn test_update_delay_too_short(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        
        let new_delay = between_u64(0, TestConstants::MINIMUM_DELAY - 1, a);
        bridge_executor.update_delay(new_delay);
    }

    #[test]
    #[should_panic(expected: ('Delay longer than max',))]
    fn test_update_delay_too_long(a: u64) {
        let bridge_executor = setup();
        cheat_caller_address(bridge_executor.contract_address, bridge_executor.contract_address, CheatSpan::TargetCalls(1));
        let new_delay = between_u64(TestConstants::MAXIMUM_DELAY + 1, BoundedInt::max(), a);
        bridge_executor.update_delay(new_delay);
    }

    #[test]
    #[should_panic(expected: ('Unauthorized Ethereum Executor',))]
    fn test_l1_handler_unauthorized() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(0);
        let _res = l1_tx.execute(3183193891, calldata_array.span()).unwrap_syscall();
    }
    
   #[test]
   #[should_panic(expected: ('Empty targets',))]
   fn test_l1_handler_empty_targets() {
       let bridge_executor = setup();
       let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
       let mut calldata_array = ArrayTrait::<felt252>::new();
       calldata_array.append(1);
       calldata_array.append(0);
       let _res = l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
   }


   #[test]
   #[should_panic(expected: ('Duplicate action',))]
    fn test_l1_handler_duplicate_action() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();

        // store one call update_delay
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (_expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        let current_hash : u256 = *hash_array.at(0);
        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("queued_actions"), // Providing variable name
                array![current_hash.low.into(), current_hash.high.into()].span(),   // Providing mapping key 
            ),
            array![1].span()
        );
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
   }

    #[test]
    fn test_l1_handler_one_call() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();

        // store one call update_delay
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        let mut spy = spy_events(SpyOn::One(bridge_executor.contract_address));
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        spy.assert_emitted(@array![
            (
                bridge_executor.contract_address,
                BridgeExecutor::Event::ActionsSetQueued(
                    BridgeExecutor::ActionsSetQueued{
                        actions_set_id: 0,
                        actions_set: expected_action_set
                    }
                )
            )
        ]);
        let expected_hash = *hash_array.at(0);
        let is_action_queued = bridge_executor.is_action_queued(expected_hash);
        assert(is_action_queued == true, 'fail update aq');
        let loaded_action = bridge_executor.get_actions_set_by_id(0);
        assert(loaded_action == expected_action_set, 'fail load as');
        let action_set_count = bridge_executor.get_actions_set_count();
        assert(action_set_count == 1, 'invalid sc');
    }

    #[test]
    fn test_l1_handler_one_call_one_delegate() {
        let bridge_executor = setup();
        let (_, contract_class_hash) = setup_mock();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();


        // store one call update_delay
        calldata_array.append(12);
        calldata_array.append(2);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        calldata_array.append(1);
        calldata_array.append(contract_class_hash);
        calldata_array.append(TestConstants::INCR_COUNTER_SELECTOR);
        let increase_value: u256 = 722;
        calldata_array.append(2);
        calldata_array.append(increase_value.low.into());
        calldata_array.append(increase_value.high.into());

        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        let mut spy = spy_events(SpyOn::One(bridge_executor.contract_address));
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        spy.assert_emitted(@array![
            (
                bridge_executor.contract_address,
                BridgeExecutor::Event::ActionsSetQueued(
                    BridgeExecutor::ActionsSetQueued{
                        actions_set_id: 0,
                        actions_set: expected_action_set
                    }
                )
            )
        ]);

        let expected_hash = *hash_array.at(0);
        let is_action_queued = bridge_executor.is_action_queued(expected_hash);
        assert(is_action_queued == true, 'fail update aq1');

        let expected_hash_2 = *hash_array.at(1);
        let is_action_queued = bridge_executor.is_action_queued(expected_hash_2);
        assert(is_action_queued == true, 'fail update aq2');
        
        let action_set_count = bridge_executor.get_actions_set_count();
        assert(action_set_count == 1, 'invalid sc');

        let loaded_action = bridge_executor.get_actions_set_by_id(0);
        assert(loaded_action == expected_action_set, 'fail load as');
    }

    #[test]
    #[should_panic(expected: ('Invalid actions set id',))]
    fn test_get_current_state_invalid_action_set_id() {
        let bridge_executor = setup();
        let _current_state = bridge_executor.get_current_state(0);
    }

    #[test]
    fn test_get_current_state() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("canceled"), 
                array![0].span(),  
            ),
            array![1].span()
        );
        let _current_state = bridge_executor.get_current_state(0);
        assert(_current_state == ActionSetState::Canceled(()), 'invalid as_can');

        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("canceled"), 
                array![0].span(),  
            ),
            array![0].span()
        );

        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("executed"), 
                array![0].span(),  
            ),
            array![1].span()
        );

        let _current_state = bridge_executor.get_current_state(0);
        assert(_current_state == ActionSetState::Executed(()), 'invalid as_exe');

        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("executed"), 
                array![0].span(),  
            ),
            array![0].span()
        );

        let _current_state = bridge_executor.get_current_state(0);
        assert(_current_state == ActionSetState::Queued(()), 'invalid as_exe');

        
        let timestamp_expired = bridge_executor.get_delay() + get_block_timestamp() + bridge_executor.get_grace_period() + 1;
        cheat_block_timestamp(bridge_executor.contract_address, timestamp_expired, CheatSpan::TargetCalls(1));
        let _current_state = bridge_executor.get_current_state(0);
        assert(_current_state == ActionSetState::Expired(()), 'invalid as_exe');
    }

    #[test]
    #[should_panic(expected: ('Not guardian',))]
    fn test_cancel_only_guardian() {
        let bridge_executor = setup();
        bridge_executor.cancel(0);
    }

    

    #[test]
    #[should_panic(expected: ('Only Queued Actions',))]
    fn test_cancel_only_queued_actions() {
        let bridge_executor = setup();        
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("canceled"), 
                array![0].span(),  
            ),
            array![1].span()
        );
        cheat_caller_address(bridge_executor.contract_address, TestConstants::GUARDIAN.try_into().unwrap(), CheatSpan::TargetCalls(1));
        bridge_executor.cancel(0);
    }

    #[test]
    fn test_cancel() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        let (_expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        
        cheat_caller_address(bridge_executor.contract_address, TestConstants::GUARDIAN.try_into().unwrap(), CheatSpan::TargetCalls(1));
        bridge_executor.cancel(0);

        let current_state = bridge_executor.get_current_state(0);
        assert(current_state == ActionSetState::Canceled(()), 'cancel failed');

        let is_action_queued = bridge_executor.is_action_queued(*hash_array.at(0));
        assert(is_action_queued == false, 'action_not_queued');
    }

    #[test]
    #[should_panic(expected: ('Only Queued Actions',))]
    fn test_execute_only_queued_actions() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        store(
            bridge_executor.contract_address, 
            map_entry_address(
                selector!("canceled"), 
                array![0].span(),  
            ),
            array![1].span()
        );
        bridge_executor.execute(0);
    }

    #[test]
    #[should_panic(expected: ('Timelock Not Finished',))]
    fn test_execute_timelock_not_finished() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        cheat_block_timestamp(bridge_executor.contract_address, execution_time_expected, CheatSpan::TargetCalls(1));
        bridge_executor.execute(0);
    }

    #[test]
    fn test_execute_self_call() {
        let bridge_executor = setup();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        calldata_array.append(6);
        calldata_array.append(1);
        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        calldata_array.append(delay);
        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (_expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        
        
        let mut spy = spy_events(SpyOn::One(bridge_executor.contract_address));
        cheat_caller_address(bridge_executor.contract_address, TestConstants::GUARDIAN.try_into().unwrap(), CheatSpan::TargetCalls(1));
        bridge_executor.execute(0);
        
        let mut returned_data_expected: Array<Span<felt252>> = ArrayTrait::new();
        let mut returned_data_call_update_delay : Array<felt252> = ArrayTrait::new();
        returned_data_expected.append(returned_data_call_update_delay.span());
        spy.assert_emitted(@array![
            (
                bridge_executor.contract_address,
                BridgeExecutor::Event::ActionsSetExecuted(
                    BridgeExecutor::ActionsSetExecuted{
                        actions_set_id: 0,
                        caller: TestConstants::GUARDIAN.try_into().unwrap(),
                        returned_data: returned_data_expected
                    }
                )
            )
        ]);

        let current_state = bridge_executor.get_current_state(0);
        assert(current_state == ActionSetState::Executed(()), 'fail exec');
        let is_action_queued = bridge_executor.is_action_queued(*hash_array.at(0));
        assert(is_action_queued == false, 'action_not_queued');
        let new_delay = bridge_executor.get_delay();
        assert(new_delay == delay.try_into().unwrap(), 'failed exec u_d')
    }

    #[test]
    fn test_execute_self_call_and_ext_call() {
        let bridge_executor = setup();
        let (mock, _) = setup_mock();
        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        let increase_amount : u256 = 4;

        calldata_array.append(12);

        calldata_array.append(2);

        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        calldata_array.append(delay);

        calldata_array.append(0);
        calldata_array.append(mock.contract_address.into());
        calldata_array.append(TestConstants::INCR_COUNTER_SELECTOR);
        calldata_array.append(2);
        calldata_array.append(increase_amount.low.into());
        calldata_array.append(increase_amount.high.into());


        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (_expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();
        
        
        let mut spy = spy_events(SpyOn::One(bridge_executor.contract_address));
        cheat_caller_address(bridge_executor.contract_address, TestConstants::GUARDIAN.try_into().unwrap(), CheatSpan::TargetCalls(1));
        bridge_executor.execute(0);
        
        let mut returned_data_expected: Array<Span<felt252>> = ArrayTrait::new();
        let mut returned_data_call_update_delay : Array<felt252> = ArrayTrait::new();
        let mut returned_data_call_increase_counter : Array<felt252> = ArrayTrait::new();
        returned_data_expected.append(returned_data_call_update_delay.span());
        returned_data_call_increase_counter.append(increase_amount.low.into());
        returned_data_call_increase_counter.append(increase_amount.high.into());
        returned_data_expected.append(returned_data_call_increase_counter.span());
    
        spy.assert_emitted(@array![
            (
                bridge_executor.contract_address,
                BridgeExecutor::Event::ActionsSetExecuted(
                    BridgeExecutor::ActionsSetExecuted{
                        actions_set_id: 0,
                        caller: TestConstants::GUARDIAN.try_into().unwrap(),
                        returned_data: returned_data_expected
                    }
                )
            )
        ]);

        let current_state = bridge_executor.get_current_state(0);
        assert(current_state == ActionSetState::Executed(()), 'fail exec');
        let is_action_queued_1 = bridge_executor.is_action_queued(*hash_array.at(0));
        assert(is_action_queued_1 == false, 'action_not_queued_1');
        let is_action_queued_2 = bridge_executor.is_action_queued(*hash_array.at(1));
        assert(is_action_queued_2 == false, 'action_not_queued_2');
        let new_delay = bridge_executor.get_delay();
        assert(new_delay == delay.try_into().unwrap(), 'failed exec u_d');
        let new_counter_total = mock.get_counter();
        assert(new_counter_total == increase_amount, 'failed exec i_c');
    }

    #[test]
    fn test_execute_self_call_ext_call_ext_deleg_call() {
        let bridge_executor = setup();
        let (mock, mock_hash) = setup_mock();

        let mut l1_tx = L1HandlerTrait::new(bridge_executor.contract_address, TestConstants::SELECTOR);
        let mut calldata_array = ArrayTrait::<felt252>::new();
        
        let delay : felt252= (TestConstants::MAXIMUM_DELAY / 2).into();
        let increase_amount : u256 = 4;

        calldata_array.append(18);

        calldata_array.append(3);

        calldata_array.append(0);
        calldata_array.append(bridge_executor.contract_address.into());
        calldata_array.append(TestConstants::UPD_DELAY_SELECTOR);
        calldata_array.append(1);
        calldata_array.append(delay);

        calldata_array.append(0);
        calldata_array.append(mock.contract_address.into());
        calldata_array.append(TestConstants::INCR_COUNTER_SELECTOR);
        calldata_array.append(2);
        calldata_array.append(increase_amount.low.into());
        calldata_array.append(increase_amount.high.into());

        calldata_array.append(1);
        calldata_array.append(mock_hash);
        calldata_array.append(TestConstants::INCR_COUNTER_SELECTOR);
        calldata_array.append(2);
        calldata_array.append(increase_amount.low.into());
        calldata_array.append(increase_amount.high.into());


        let execution_time_expected = bridge_executor.get_delay() + get_block_timestamp();
        let (_expected_action_set, hash_array): (ActionSet, Array<u256>) = build_set_action_from_calldata(calldata_array.span(), execution_time_expected);
        l1_tx.execute(TestConstants::ETHEREUM_GOVERNANCE_EXECUTOR, calldata_array.span()).unwrap_syscall();


        let mut spy = spy_events(SpyOn::One(bridge_executor.contract_address));
        cheat_caller_address(bridge_executor.contract_address, TestConstants::GUARDIAN.try_into().unwrap(), CheatSpan::TargetCalls(1));
        bridge_executor.execute(0);

        let mut returned_data_expected: Array<Span<felt252>> = ArrayTrait::new();
        let mut returned_data_call_update_delay : Array<felt252> = ArrayTrait::new();
        let mut returned_data_call_increase_counter : Array<felt252> = ArrayTrait::new();
        returned_data_expected.append(returned_data_call_update_delay.span());
        returned_data_call_increase_counter.append(increase_amount.low.into());
        returned_data_call_increase_counter.append(increase_amount.high.into());
        returned_data_expected.append(returned_data_call_increase_counter.span());
        returned_data_expected.append(returned_data_call_increase_counter.span());
    
        spy.assert_emitted(@array![
            (
                bridge_executor.contract_address,
                BridgeExecutor::Event::ActionsSetExecuted(
                    BridgeExecutor::ActionsSetExecuted{
                        actions_set_id: 0,
                        caller: TestConstants::GUARDIAN.try_into().unwrap(),
                        returned_data: returned_data_expected
                    }
                )
            )
        ]);

        let current_state = bridge_executor.get_current_state(0);
        assert(current_state == ActionSetState::Executed(()), 'fail exec');
        let is_action_queued_1 = bridge_executor.is_action_queued(*hash_array.at(0));
        assert(is_action_queued_1 == false, 'action_not_queued_1');
        let is_action_queued_2 = bridge_executor.is_action_queued(*hash_array.at(1));
        assert(is_action_queued_2 == false, 'action_not_queued_2');
        let is_action_queued_3 = bridge_executor.is_action_queued(*hash_array.at(2));
        assert(is_action_queued_3 == false, 'action_not_queued_3');
        let new_delay = bridge_executor.get_delay();
        assert(new_delay == delay.try_into().unwrap(), 'failed exec u_d');
        let new_counter_total = mock.get_counter();
        assert(new_counter_total == increase_amount, 'failed exec i_c');

        let result_self_counter = load(bridge_executor.contract_address, selector!("counter"), 2);
        assert(u256{low: (*result_self_counter.at(0)).try_into().unwrap(), high: (*result_self_counter.at(1)).try_into().unwrap() } == increase_amount, 'fail delegat i_c');
    }

}