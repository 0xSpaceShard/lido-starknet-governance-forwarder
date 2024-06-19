/// @title The BridgeExecutor for cross-chain governance
/// @author @nimbora 2024
#[starknet::contract]
pub mod BridgeExecutor {

    // Importing required modules and types from the starknet crate and other dependencies
    use starknet::{ContractAddress, EthAddress, get_block_timestamp, ClassHash, get_caller_address, get_contract_address, SyscallResultTrait, syscalls::{
        call_contract_syscall, library_call_syscall,
    }};
    use lido_forward::bridge_executor::interface::{ActionSet, ActionSetState, IBridgeExecutor, CallOrDelegateCall}; 
    use core::integer::{u128_byte_reverse};

    // Storage definition for BridgeExecutor
    #[storage]
    struct Storage {
        ethereum_governance_executor: EthAddress,
        delay: u64,
        grace_period: u64,
        minimum_delay: u64,
        maximum_delay: u64,
        guardian: ContractAddress,
        actions_set_counter: u32,
        executed: LegacyMap<u32, bool>,
        canceled: LegacyMap<u32, bool>,
        execution_time: LegacyMap<u32, u64>,
        with_delegate_calls: LegacyMap<(u32, u32), bool>,
        calls_len: LegacyMap<u32, u32>,
        calls_to: LegacyMap<(u32, u32), felt252>,
        calls_selector: LegacyMap<(u32, u32), felt252>,
        calls_calldata_len: LegacyMap<(u32, u32), u32>,
        calls_calldata: LegacyMap<(u32, u32, u32), felt252>,
        queued_actions: LegacyMap<u256, bool>
    }

    // Events for contract state changes and action results
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        EthereumGovernanceExecutorUpdate: EthereumGovernanceExecutorUpdate,
        GuardianUpdate: GuardianUpdate,
        DelayUpdate: DelayUpdate,
        GracePeriodUpdate: GracePeriodUpdate,
        MinimumDelayUpdate: MinimumDelayUpdate,
        MaximumDelayUpdate: MaximumDelayUpdate,
        ActionsSetQueued: ActionsSetQueued,
        ActionsSetExecuted: ActionsSetExecuted,
        ActionsSetCanceled: ActionsSetCanceled
    }

    #[derive(Drop, starknet::Event)]
    struct EthereumGovernanceExecutorUpdate {
        previous_ethereum_governance_executor: EthAddress,
        new_ethereum_governance_executor: EthAddress
    }

    #[derive(Drop, starknet::Event)]
    struct GuardianUpdate {
        previous_guardian: ContractAddress,
        new_guardian: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct DelayUpdate {
        previous_delay: u64,
        new_delay: u64
    }

    #[derive(Drop, starknet::Event)]
    struct GracePeriodUpdate {
        previous_grace_period: u64,
        new_grace_period: u64
    }

    #[derive(Drop, starknet::Event)]
    struct MinimumDelayUpdate {
        previous_minimum_delay: u64,
        new_minimum_delay: u64
    }

    #[derive(Drop, starknet::Event)]
    struct MaximumDelayUpdate {
        previous_maximum_delay: u64,
        new_maximum_delay: u64
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActionsSetQueued {
        pub actions_set_id: u32,
        pub actions_set: ActionSet
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActionsSetExecuted {
        pub actions_set_id: u32,
        pub caller: ContractAddress,
        pub returned_data: Array<Span<felt252>>
    }

    #[derive(Drop, starknet::Event)]
    struct ActionsSetCanceled {
        actions_set_id: u32
    }

    
    
    /// Module `Errors` defines constant error messages used across the BridgeExecutor contract.
    /// These error messages are used to indicate various types of failures or invalid operations
    /// attempted on the contract, improving clarity and debuggability.
    mod Errors {
        pub const INVALID_ACTIONS_SET_ID: felt252 = 'Invalid actions set id'; // Error when a non-existent action set ID is referenced.
        pub const DELAY_SHORTER_THAN_MIN: felt252 = 'Delay shorter than min'; // Error when the set delay is below the defined minimum.
        pub const DELAY_LONGER_THAN_MAX: felt252 = 'Delay longer than max'; // Error when the set delay exceeds the defined maximum.
        pub const ONLY_CALLABLE_BY_THIS: felt252 = 'Only callable by this'; // Error for functions that must be called by the contract itself.
        pub const GRACE_PERIOD_TOO_SHORT: felt252 = 'Grace period too short'; // Error when the grace period is set too short.
        pub const MINIMUM_DELAY_TOO_LONG: felt252 = 'Minimum delay too long'; // Error when the minimum delay is set longer than permissible.
        pub const MAXIMUM_DELAY_TOO_SHORT: felt252 = 'Maximum delay too short'; // Error when the maximum delay is set shorter than permissible.
        pub const INVALID_INIT_PARAMS: felt252 = 'Invalid init params'; // Error for invalid initialization parameters during contract deployment.
        pub const UNAUTHORIZED_ETHEREUM_EXECUTOR: felt252 = 'Unauthorized Ethereum Executor'; // Error when an unauthorized address attempts an Ethereum executor operation.
        pub const NOT_GUARDIAN: felt252 = 'Not guardian'; // Error when a non-guardian address attempts a guardian-only operation.
        pub const EMPTY_TARGETS: felt252 = 'Empty targets'; // Error when an operation is attempted with no target addresses specified.
        pub const DUPLICATE_ACTIONS: felt252 = 'Duplicate action'; // Error when an action is queued that duplicates an existing one.
        pub const ONLY_QUEUED_ACTIONS: felt252 = 'Only Queued Actions'; // Error when trying to execute or cancel an action that is not queued.
        pub const TIMELOCK_NOT_FINISHED: felt252 = 'Timelock Not Finished'; // Error when an action is attempted to be executed before its timelock has expired.
    }

    /// Module `Constants` defines immutable values used throughout the BridgeExecutor contract.
    /// These constants ensure consistency and maintainability of key parameters that affect contract logic.
    pub mod Constants {
        pub const MINIMUM_GRACE_PERIOD: u64 = 60 * 10; // Defines the minimum grace period in seconds. Set to 600 seconds (10 minutes).
    }


    /// Constructor for initializing a new instance of the BridgeExecutor contract.
    /// This function sets up the initial state of the contract, including various timing constraints
    /// and special administrative roles.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the contract state.
    /// * `delay` - The initial delay before an action set becomes executable.
    /// * `grace_period` - The period after the delay during which the action must be executed.
    /// * `minimum_delay` - The minimum allowable delay for action sets.
    /// * `maximum_delay` - The maximum allowable delay for action sets.
    /// * `guardian` - The contract address with guardian role, capable of emergency interventions.
    /// * `ethereum_governance_executor` - The Ethereum address authorized to execute high-level changes.
    ///
    /// # Panics
    /// The constructor will panic if any of the provided initialization parameters are invalid,
    /// e.g., if the grace period is below the minimum or if the delays are not within the allowed range.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        delay: u64,
        grace_period: u64,
        minimum_delay: u64,
        maximum_delay: u64,
        guardian: ContractAddress,
        ethereum_governance_executor: EthAddress
    ) {
        assert(
            grace_period >= Constants::MINIMUM_GRACE_PERIOD
                || minimum_delay < maximum_delay
                || delay >= minimum_delay
                || delay <= maximum_delay,
            Errors::INVALID_INIT_PARAMS
        );
        self._update_delay(delay);
        self._update_grace_period(grace_period);
        self._update_minimum_delay(minimum_delay);
        self._update_maximum_delay(maximum_delay);
        self._update_guardian(guardian);
        self._update_ethereum_governance_executor(ethereum_governance_executor);
    }


    /// L1 handler for processing responses from Ethereum.
    /// This function is intended to be called only through StarkNet's messaging system from Ethereum,
    /// allowing the handling of specific actions directed by the Ethereum governance executor.
    ///
    /// # Attributes
    /// * `#[l1_handler]` - Marks this function as a handler for messages coming from L1 (Ethereum),
    ///   ensuring it's only callable through StarkNet's L1-to-L2 messaging system.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the contract state.
    /// * `from_address` - The Ethereum address from which the message originates.
    /// * `data` - An array of `felt252` values representing the calldata or data sent from L1.
    ///
    /// # Panics
    /// * Panics if the message is not sent by the authorized Ethereum governance executor, ensuring
    ///   that only authorized messages can dictate actions within this contract.
    ///
    /// # Behavior
    /// * This function reads the current delay and the block timestamp to compute the execution time
    ///   for actions. It then increments the action set counter and stores the incoming data as a new
    ///   action set, which is then queued for future execution.
    ///
    /// # Events
    /// * Emits `ActionsSetQueued` to signal that a new set of actions has been successfully parsed
    ///   and stored, awaiting its execution time.
    #[l1_handler]
    fn handle_response(ref self: ContractState, from_address: felt252, data: Array<felt252>) {
        
        // Reads the currently authorized Ethereum governance executor's address from storage.
        let ethereum_governance_executor = self.ethereum_governance_executor.read();
        // Asserts that the sender of the message matches the authorized executor's address.
        assert(ethereum_governance_executor.into() == from_address, Errors::UNAUTHORIZED_ETHEREUM_EXECUTOR);
        // Calculates the execution time for the new actions set by adding the current delay to the current block timestamp.
        let execution_time = self.delay.read() + get_block_timestamp();
        // Reads the current action set counter and increments it for the new actions set.
        let actions_set_id = self.actions_set_counter.read();


        // Parses the incoming data and stores it as a new actions set, also calculating and storing the execution time.
        let actions_set = self._parse_data_and_store_actions(data.span(), execution_time, actions_set_id);
        
        // Emits an event indicating that a new actions set has been queued.
        self.emit(ActionsSetQueued { actions_set_id, actions_set });
    }

    /// Implementation of the `BridgeExecutorImpl` for the `IBridgeExecutor` interface.
    #[abi(embed_v0)]
    impl BridgeExecutorImpl of IBridgeExecutor<ContractState> {
        
        // GETTERS

        /// Returns the Ethereum governance executor address.
        /// This address is authorized to perform specific governance actions within the contract.
        fn get_ethereum_governance_executor(self: @ContractState) -> EthAddress {
            self.ethereum_governance_executor.read()
        }

        /// Returns the current delay set for action execution.
        /// This delay is the minimum time that must pass before an action set becomes executable.
        fn get_delay(self: @ContractState) -> u64 {
            self.delay.read()
        }

        /// Returns the grace period during which an action set must be executed.
        fn get_grace_period(self: @ContractState) -> u64 {
            self.grace_period.read()
        }

        /// Returns the minimum allowable delay for scheduling action sets.
        fn get_minimum_delay(self: @ContractState) -> u64 {
            self.minimum_delay.read()
        }

        /// Returns the maximum allowable delay for scheduling action sets.
        fn get_maximum_delay(self: @ContractState) -> u64 {
            self.maximum_delay.read()
        }

        /// Returns the guardian's contract address.
        /// The guardian has special permissions for emergency actions.
        fn get_guardian(self: @ContractState) -> ContractAddress {
            self.guardian.read()
        }

        /// Returns the count of action sets managed by the contract.
        fn get_actions_set_count(self: @ContractState) -> u32 {
            self.actions_set_counter.read()
        }

        /// Retrieves an action set by its ID.
        /// Provides detailed information about the specific action set.
        fn get_actions_set_by_id(self: @ContractState, action_set_id: u32) -> ActionSet {
            self._load_actions_set_by_id(action_set_id)
        }

        /// Determines the current state of an action set (queued, executed, canceled, etc.).
        fn get_current_state(self: @ContractState, action_set_id: u32) -> ActionSetState {
            self._get_current_state(action_set_id)
        }

        /// Checks whether a specific action, identified by its hash, is currently queued.
        fn is_action_queued(self: @ContractState, action_hash: u256) -> bool {
            self.queued_actions.read(action_hash)
        }


        // SETTERS


        /// Updates the Ethereum governance executor address.
        /// This function can only be called by the contract itself to ensure secure management.
        /// # Arguments
        /// * `ethereum_governance_executor` - The new Ethereum address to be set as the governance executor.
        fn update_ethereum_governance_executor(ref self: ContractState, ethereum_governance_executor: EthAddress) {
            self._only_this(); // Ensures only the contract itself can call this function.
            self._update_ethereum_governance_executor(ethereum_governance_executor);
        }

        /// Updates the guardian address.
        /// The guardian role can take critical actions in emergency scenarios.
        /// # Arguments
        /// * `guardian` - The new ContractAddress to be set as the guardian.
        fn update_guardian(ref self: ContractState, guardian: ContractAddress) {
            self._only_this(); // Ensures only the contract itself can call this function.
            self._update_guardian(guardian);
        }

        /// Updates the delay parameter of the contract.
        /// The delay is the minimum time that must pass before an action can be executed.
        /// # Arguments
        /// * `delay` - The new delay time in seconds.
        fn update_delay(ref self: ContractState, delay: u64) {
            self._only_this(); // Ensures only the contract itself can call this function.
            self._validate_delay(delay); // Validates that the new delay is within defined limits.
            self._update_delay(delay);
        }

        /// Updates the grace period of the contract.
        /// The grace period is the time after the delay during which an action must be executed.
        /// # Arguments
        /// * `grace_period` - The new grace period in seconds.
        fn update_grace_period(ref self: ContractState, grace_period: u64) {
            self._only_this(); // Ensures only the contract itself can call this function.
            assert(Constants::MINIMUM_GRACE_PERIOD <= grace_period, Errors::GRACE_PERIOD_TOO_SHORT); // Checks if the new grace period meets minimum requirements.
            self._update_grace_period(grace_period);
        }

        /// Updates the minimum delay allowed for action execution.
        /// # Arguments
        /// * `minimum_delay` - The new minimum delay in seconds.
        fn update_minimum_delay(ref self: ContractState, minimum_delay: u64) {
            self._only_this(); // Ensures only the contract itself can call this function.
            let maximum_delay = self.maximum_delay.read(); // Reads the current maximum delay.
            assert(maximum_delay > minimum_delay, Errors::MINIMUM_DELAY_TOO_LONG); // Ensures the new minimum delay is less than the maximum.
            self._update_minimum_delay(minimum_delay);
        }

        /// Updates the maximum delay allowed for action execution.
        /// # Arguments
        /// * `maximum_delay` - The new maximum delay in seconds.
        fn update_maximum_delay(ref self: ContractState, maximum_delay: u64) {
            self._only_this(); // Ensures only the contract itself can call this function.
            let minimum_delay = self.minimum_delay.read(); // Reads the current minimum delay.
            assert(maximum_delay > minimum_delay, Errors::MAXIMUM_DELAY_TOO_SHORT); // Ensures the new maximum delay is greater than the minimum.
            self._update_maximum_delay(maximum_delay);
        }

        // LOGIC 

        /// Executes an action set if it is queued and the timelock has finished.
        /// This function checks the state of an action set and processes each call within it.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `actions_set_id` - The identifier for the action set to be executed.
        ///
        /// # Panics
        /// * Panics if the action set is not in the 'Queued' state, ensuring only ready action sets are processed.
        /// * Panics if the current block timestamp is not greater than the execution time, enforcing timelock restrictions.
        fn execute(ref self: ContractState, actions_set_id: u32) {
            // Ensure the action set is queued and ready for execution.
            assert(self._get_current_state(actions_set_id) == ActionSetState::Queued(()), Errors::ONLY_QUEUED_ACTIONS);
            // Load the action set details from storage.
            let actions_set = self._load_actions_set_by_id(actions_set_id);
            // Get the current block timestamp.
            let block_timestamp = get_block_timestamp();
            // Ensure the execution time has passed.
            assert(block_timestamp < actions_set.execution_time, Errors::TIMELOCK_NOT_FINISHED);
            // Mark the action set as executed.
            self.executed.write(actions_set_id, true);
            // Initialize an array to collect returned data from executed transactions.
            let mut returned_data: Array<Span<felt252>> = ArrayTrait::new();
            // Execute each call in the action set.
            let mut index = 0;
            while index != actions_set.calls.len() {
                returned_data.append(self._execute_transation(*actions_set.calls.at(index), *actions_set.with_delegate_calls.at(index), actions_set.execution_time));
                index += 1;
            };
            // Get the address of the caller.
            let caller = get_caller_address();
            // Emit an event indicating the action set has been executed.
            self.emit( ActionsSetExecuted{ actions_set_id, caller, returned_data });
        }

        
        /// Cancels a queued action set, marking it as canceled and performing cleanup.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `actions_set_id` - The identifier for the action set to be canceled.
        ///
        /// # Panics
        /// * Panics if the action set is not in the 'Queued' state, ensuring that only pending action sets can be canceled.
        /// * Panics if the function is not called by the guardian, enforcing role-based security.
        fn cancel(ref self: ContractState, actions_set_id: u32) {
            // Ensure only the guardian can call this function.
            self._only_guardian();
            // Ensure the action set is still queued before canceling.
            assert(self._get_current_state(actions_set_id) == ActionSetState::Queued(()), Errors::ONLY_QUEUED_ACTIONS);
            // Load the action set details from storage.
            let actions_set = self._load_actions_set_by_id(actions_set_id);
            // Mark the action set as canceled.
            self.canceled.write(actions_set_id, true);
            // Cancel each transaction in the action set.
            let mut index = 0;
            while index != actions_set.calls.len() {
                self._cancel_transaction(*actions_set.calls.at(index), *actions_set.with_delegate_calls.at(index), actions_set.execution_time);
                index += 1;
            };
            // Emit an event indicating the action set has been canceled.
            self.emit(ActionsSetCanceled { actions_set_id });
        }

    }


    #[generate_trait]
    impl InternalImpl of InternalTrait {


        /// Ensures that the function is only called by the contract itself.
        /// This is used to restrict certain operations to be self-executed by the contract to avoid external abuses.
        fn _only_this(self: @ContractState) {
            let caller_address = get_caller_address(); // Retrieves the address of the caller.
            let this = get_contract_address(); // Retrieves the contract's own address.
            assert(caller_address == this, Errors::ONLY_CALLABLE_BY_THIS); // Ensures the caller is the contract itself.
        }

        /// Ensures that the function is only called by the designated guardian.
        /// The guardian is a special role with permissions to perform sensitive operations.
        fn _only_guardian(self: @ContractState) {
            let caller_address = get_caller_address(); // Retrieves the address of the caller.
            let guardian = self.guardian.read(); // Retrieves the address of the guardian from storage.
            assert(caller_address == guardian, Errors::NOT_GUARDIAN); // Ensures the caller is the guardian.
        }


        /// Retrieves the current state of an action set by its ID.
        /// This function helps determine if an action set can be executed, canceled, or has expired.
        fn _get_current_state(self: @ContractState, action_set_id: u32) -> ActionSetState {
            let actions_set_counter = self.actions_set_counter.read(); // Reads the last action set counter.
            assert(actions_set_counter > action_set_id, Errors::INVALID_ACTIONS_SET_ID); // Validates the action set ID.
            let action_set = self._load_actions_set_by_id(action_set_id); // Loads the action set details.
            if (action_set.canceled) {
                ActionSetState::Canceled(())
            } else if (action_set.executed) {
                ActionSetState::Executed(())
            } else {
                let block_timestamp = get_block_timestamp(); // Gets the current block timestamp.
                let grace_period = self.grace_period.read(); // Reads the grace period.
                if (block_timestamp > action_set.execution_time + grace_period) {
                    ActionSetState::Expired(())
                } else {
                    ActionSetState::Queued(())
                }
            }
        }

        /// Executes a transaction within an action set, potentially using a delegate call.
        /// This function handles the execution of individual transactions, managing both direct and delegate calls.
        fn _execute_transation(ref self: ContractState, call : CallOrDelegateCall, with_delegate_call: bool, execution_time: u64) -> Span<felt252> {
            let action_hash = self._get_action_hash(with_delegate_call.into(), call.to, call.selector, call.calldata, execution_time); // Computes the hash of the action.
            self.queued_actions.write(action_hash, false); // Marks the action as not queued.
            if(with_delegate_call){
                library_call_syscall(call.to.try_into().unwrap(), call.selector, call.calldata).unwrap_syscall() // Executes a library call if delegate is true.
            } else {
                call_contract_syscall(call.to.try_into().unwrap(), call.selector, call.calldata).unwrap_syscall() // Executes a standard contract call otherwise.
            }
        }

        /// Cancels a transaction within an action set, marking its action hash as not queued.
        /// This function is used to clean up after canceling an action set, ensuring no actions remain flagged as queued.
        fn _cancel_transaction(ref self: ContractState, call : CallOrDelegateCall, with_delegate_call: bool, execution_time: u64) {
            let action_hash = self._get_action_hash(with_delegate_call.into(), call.to, call.selector, call.calldata, execution_time); // Computes the hash of the action.
            self.queued_actions.write(action_hash, false); // Marks the action as not queued.
        }

        /// Parses the incoming data and stores it as an action set in the contract's storage.
        /// This function is responsible for decomposing the received data into individual transaction components,
        /// recording them, and preparing them for future execution.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `data` - A span of `felt252` representing the data for an action set.
        /// * `execution_time` - The timestamp at which the action set becomes executable.
        /// * `actions_set_id` - The identifier for the new action set.
        ///
        /// # Returns
        /// * `ActionSet` - A new action set created from the parsed data, ready for queuing.
        ///
        /// # Panics
        /// * Panics if the first element of data, which represents the length of calls, is zero.
        ///   This check ensures that the parsed data includes at least one callable action.
        fn _parse_data_and_store_actions(ref self: ContractState, data : Span<felt252>, execution_time: u64, actions_set_id: u32) -> ActionSet {
            // Read the length of calls from the first element of the data array.

            let call_len: u32 = (*data.at(0)).try_into().unwrap();
            assert(call_len != 0, Errors::EMPTY_TARGETS); // Ensure there are targets to execute.
            self.calls_len.write(actions_set_id, call_len);
            self.execution_time.write(actions_set_id, execution_time); // Store the execution time.

            // Initialize containers for delegate call flags and call details.
            let mut with_delegate_calls = ArrayTrait::<bool>::new();
            let mut calls = ArrayTrait::<CallOrDelegateCall>::new();


            // Process each call described in the data array.
            let mut index_action: u32 = 0;
            let mut current_index: u32 = 1; // Start reading from the second element.
            while index_action != call_len {
                // Read and convert the delegate call flag from data.
                let elem_with_delegate_calls: felt252 = *data.at(current_index); 
                let elem_with_delegate_calls_bool = self._felt_to_bool(elem_with_delegate_calls);
                self.with_delegate_calls.write((actions_set_id, index_action), elem_with_delegate_calls_bool);
                with_delegate_calls.append(elem_with_delegate_calls_bool);

                // Read the contract address for the call.
                let elem_to = *data.at(current_index + 1);
                self.calls_to.write((actions_set_id, index_action), elem_to);

                // Read the function selector.
                let elem_selector = *data.at(current_index + 2);
                self.calls_selector.write((actions_set_id, index_action), elem_selector);

                // Read and process call data length and call data.
                let elem_calldata_len: u32 = (*data.at(current_index + 3)).try_into().unwrap();
                self.calls_calldata_len.write((actions_set_id, index_action), elem_calldata_len);

                let mut index_calldata = 0;
                let mut elem_calldata = ArrayTrait::<felt252>::new();
                while index_calldata != elem_calldata_len {
                    let elem_elem_calldata = *data.at(current_index + index_calldata + 4);
                    elem_calldata.append(elem_elem_calldata);
                    self.calls_calldata.write((actions_set_id, index_action, index_calldata), elem_elem_calldata);
                    index_calldata += 1;
                };

                // Combine call details into a structure and save it.
                let elem_calldata_span = elem_calldata.span();
                self._check_and_save_action_hash(elem_with_delegate_calls, elem_to, elem_selector, elem_calldata_span, execution_time);
                let elem_call : CallOrDelegateCall = CallOrDelegateCall {
                    to: elem_to,
                    selector: elem_selector,
                    calldata: elem_calldata_span
                };
                calls.append(elem_call);
                current_index += 4 + elem_calldata_len; // Move to the next call's data.
                index_action += 1;
            };
            // Increment the action set counter post processing.
            self.actions_set_counter.write(actions_set_id + 1);
            // Return the newly created action set.
            ActionSet {
                calls: calls.span(),
                with_delegate_calls: with_delegate_calls.span(),
                execution_time: execution_time,
                executed: false,
                canceled: false,
            }
        }


        /// Converts a `felt252` value into a boolean.
        /// This is a utility function used to interpret Cairo `felt` values as boolean flags.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `felt_to_convert` - The `felt252` value to be converted to boolean.
        ///
        /// # Returns
        /// * `bool` - The boolean interpretation of the input `felt`.
        ///
        /// # Panics
        /// * Panics if the input `felt` is neither 0 nor 1, ensuring only valid boolean values are processed.
        fn _felt_to_bool(self: @ContractState, felt_to_convert: felt252) -> bool {
            if felt_to_convert == 0 {
                false
            } else if felt_to_convert == 1 {
                true
            } else {
                panic!("NOT_BOOL"); // Ensures strict boolean inputs.
                true
            }
        }

        /// Checks and saves the hash of an action, ensuring no duplicates are queued.
        /// This function generates a hash for a given action and checks if it is already queued.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `with_delegate_calls` - Indicator if the call uses delegate call.
        /// * `to` - The contract address being called.
        /// * `selector` - The function selector of the call.
        /// * `calldata` - The input data for the call.
        /// * `execution_time` - The scheduled execution time for this action.
        ///
        /// # Panics
        /// * Panics if the action is already queued, ensuring that each action is unique.
        fn _check_and_save_action_hash(ref self: ContractState, with_delegate_calls: felt252, to: felt252, selector: felt252, calldata: Span<felt252>, execution_time: u64) {
            let action_hash = self._get_action_hash(with_delegate_calls, to, selector, calldata, execution_time);
            let is_action_queued = self.queued_actions.read(action_hash);
            assert(!is_action_queued, Errors::DUPLICATE_ACTIONS); // Prevents duplicate actions.
            self.queued_actions.write(action_hash, true); // Marks this action as queued.
        }


        /// Generates a unique hash for an action using its parameters.
        /// This hash is used to uniquely identify actions within the system, aiding in their management and execution.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `with_delegate_calls` - Indicates whether the action uses a delegate call.
        /// * `to` - The contract address to which the action is directed.
        /// * `selector` - The function selector for the action.
        /// * `calldata` - The input data for the action.
        /// * `execution_time` - The scheduled time for the action's execution.
        ///
        /// # Returns
        /// * `u256` - The unique keccak hash of the action.
        fn _get_action_hash(self: @ContractState, with_delegate_calls: felt252, to: felt252, selector: felt252, calldata: Span<felt252>, execution_time: u64) -> u256 {
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
            self._reverse_endianness(hash) // Adjusts for endianness for consistent hashing.
        }

        /// Reverses the endianness of a 256-bit unsigned integer.
        /// This is typically used for hash values where endianness needs to be consistent across different platforms or systems.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `value` - The 256-bit unsigned integer (`u256`) whose endianness is to be reversed.
        ///
        /// # Returns
        /// * `u256` - The value with reversed endianness, where the high and low parts are swapped and individually byte-reversed.
        fn _reverse_endianness(self: @ContractState, value: u256) -> u256 {
            let new_low = u128_byte_reverse(value.high); // Reverse the byte order of the high part.
            let new_high = u128_byte_reverse(value.low); // Reverse the byte order of the low part.
            u256 { low: new_low, high: new_high } // Reconstructs the u256 with swapped parts.
        }

        /// Loads a specific action set by its identifier from the contract's storage.
        /// This function retrieves all details related to an action set, reconstructing it from the stored data.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `actions_set_id` - The unique identifier for the action set to be retrieved.
        ///
        /// # Returns
        /// * `ActionSet` - The reconstructed action set, including its calls, delegate call flags, and status.
        ///
        /// # Detailed Functionality
        /// This function reads each component of an action set, including execution status flags and call details.
        /// It aggregates the information into the `ActionSet` structure for easy access and manipulation elsewhere in the contract.        
        fn _load_actions_set_by_id(self: @ContractState, actions_set_id: u32) -> ActionSet {
            // Read the status flags for the action set.
            let canceled = self.canceled.read(actions_set_id);
            let executed = self.executed.read(actions_set_id);
            let execution_time = self.execution_time.read(actions_set_id);
            // Initialize containers for the calls and delegate call flags.
            let calls_len = self.calls_len.read(actions_set_id);
            let mut with_delegate_calls = ArrayTrait::<bool>::new();
            let mut calls = ArrayTrait::<CallOrDelegateCall>::new();
            // Loop through each call in the action set and reconstruct the details.
            let mut index = 0;
            while index != calls_len {
                let elem_to = self.calls_to.read((actions_set_id, index));
                let elem_selector = self.calls_selector.read((actions_set_id, index));
                let elem_calldata_len = self.calls_calldata_len.read((actions_set_id, index));
                let mut index_calldata = 0;
                let mut elem_calldata = ArrayTrait::<felt252>::new();
                while index_calldata != elem_calldata_len {
                    let elem_elem_calldata = self.calls_calldata.read((actions_set_id, index, index_calldata));
                    elem_calldata.append(elem_elem_calldata);
                    index_calldata += 1;
                };
                let elem_call : CallOrDelegateCall = CallOrDelegateCall {
                    to: elem_to,
                    selector: elem_selector,
                    calldata: elem_calldata.span()
                };
                calls.append(elem_call);
                let elem_with_delegate_calls = self.with_delegate_calls.read((actions_set_id, index));
                with_delegate_calls.append(elem_with_delegate_calls);
                index += 1;
            };
            // Construct and return the complete action set.
            ActionSet {
                calls: calls.span(),
                with_delegate_calls: with_delegate_calls.span(),
                execution_time: execution_time,
                executed: executed,
                canceled: canceled,
            }
        }

        /// Updates the Ethereum governance executor address and emits an event with the change.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `ethereum_governance_executor` - The new Ethereum address to set as the governance executor.
        ///
        /// This function reads the current governance executor, updates to the new address, and emits an
        /// event to log the change for transparency and tracking.
        fn _update_ethereum_governance_executor(ref self: ContractState, ethereum_governance_executor: EthAddress) {
            let previous_ethereum_governance_executor = self.ethereum_governance_executor.read();
            self.ethereum_governance_executor.write(ethereum_governance_executor);
            self.emit(EthereumGovernanceExecutorUpdate { previous_ethereum_governance_executor, new_ethereum_governance_executor: ethereum_governance_executor });
        }

        /// Updates the guardian address and emits an event to record the change.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `guardian` - The new ContractAddress to set as the guardian.
        ///
        /// This function reads the current guardian address, updates it, and emits an event to ensure
        /// the change is recorded and traceable.
        fn _update_guardian(ref self: ContractState, guardian: ContractAddress) {
            let previous_guardian = self.guardian.read();
            self.guardian.write(guardian);
            self.emit(GuardianUpdate { previous_guardian, new_guardian: guardian });
        }


        /// Updates the delay parameter and emits an event for the update.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `delay` - The new delay in seconds to be set.
        ///
        /// Updates the delay before actions can be executed and logs the change via an event.
        fn _update_delay(ref self: ContractState, delay: u64) {
            let previous_delay = self.delay.read();
            self.delay.write(delay);
            self.emit(DelayUpdate { previous_delay, new_delay: delay });
        }


        /// Updates the grace period for actions and emits an update event.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `grace_period` - The new grace period in seconds.
        ///
        /// Sets a new grace period and ensures the update is recorded through an event emission.
        fn _update_grace_period(ref self: ContractState, grace_period: u64) {
            let previous_grace_period = self.grace_period.read();
            self.grace_period.write(grace_period);
            self.emit(GracePeriodUpdate { previous_grace_period, new_grace_period: grace_period });
        }

        /// Updates the minimum delay allowed for actions and emits a corresponding event.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `minimum_delay` - The new minimum delay in seconds.
        ///
        /// Adjusts the minimum allowable delay for scheduling actions and logs the change with an event.
        fn _update_minimum_delay(ref self: ContractState, minimum_delay: u64) {
            let previous_minimum_delay = self.minimum_delay.read();
            self.minimum_delay.write(minimum_delay);
            self.emit(MinimumDelayUpdate { previous_minimum_delay, new_minimum_delay: minimum_delay });
        }


        /// Updates the maximum delay allowed and emits an update event.
        ///
        /// # Arguments
        /// * `self` - A mutable reference to the contract state.
        /// * `maximum_delay` - The new maximum delay in seconds.
        ///
        /// Sets a new maximum delay limit for actions and logs the update through an event for accountability.
        fn _update_maximum_delay(ref self: ContractState, maximum_delay: u64) {
            let previous_maximum_delay = self.maximum_delay.read();
            self.maximum_delay.write(maximum_delay);
            self.emit(MaximumDelayUpdate { previous_maximum_delay, new_maximum_delay: maximum_delay });
        }


        /// Validates the provided delay to ensure it falls within the contract-specified minimum and maximum bounds.
        ///
        /// # Arguments
        /// * `self` - A reference to the contract state.
        /// * `delay` - The delay time in seconds to validate.
        ///
        /// # Panics
        /// * Panics if the delay is shorter than the minimum or longer than the maximum allowed.
        fn _validate_delay(self: @ContractState, delay: u64) {
            let minimum_delay = self.minimum_delay.read();
            let maximum_delay = self.maximum_delay.read();
            assert(delay >= minimum_delay, Errors::DELAY_SHORTER_THAN_MIN);
            assert(delay <= maximum_delay, Errors::DELAY_LONGER_THAN_MAX);
        }
        
    }
}
