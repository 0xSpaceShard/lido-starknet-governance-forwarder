# Starknet - Ethereum Governance Cross-Chain Bridges

This repository contains smart contracts and related code for governance cross-chain bridge executors. This is intended to extend protocol Governance on Ethereum to Starknet network. The codebase has been inspired from [Aave Governance Crosschain Bridges](https://github.com/aave/governance-crosschain-bridges)


The core contract is the `BridgeExecutor`, an contract that contains the logic to facilitate the queueing, delay, and execution of sets of actions on Starknet network. The  contract is implemented to facilitate the execution of arbitrary actions after governance approval on Ethereum. Once the Ethereum proposal is executed, a cross-chain transaction can queue sets of actions for execution on Starknet. Once queued, these actions cannot be executed until a certain `delay` has passed, though a specified (potentially zero) `guardian` address has the power to cancel the execution of these actions. If the delay period passes and the actions are not cancelled, the actions can be executed during the `grace period` time window by anyone on the downstream chain.

### Setup

- Clone the repository
- Install [Scarb 2.6.4](https://docs.swmansion.com/scarb/)
- Install [Snforge 0.24.0](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html)


### Compile

`scarb build`

This will compile the available smart contracts.

### Test

`scarb test`

Run the full suite of unit tests.

### Scripts 

Create a `.env` and add RPC, account address, private keys, and the bridge executor address as mentioned in the `.env.example` file.

### Starknet

**Declare**

`npx ts-node scripts_l2/declareContracts.ts --contract BridgeExecutor`

**Deploy**
`npx ts-node scripts_l2/deployContracts.ts --contract BridgeExecutor.`

**Execute**
`npx ts-node scripts_l2/execute.ts --contract BridgeExecutor.`

**Cancel**
`npx ts-node scripts_l2/cancel.ts --contract BridgeExecutor.`

### Send message from ethereum

Install Hardhat with `yarn install` and run the tasks with:
`npx hardhat <function_name> <param> --network <selected network>`

Scripts for basic functions can be run directly such as `update_guardian`, `update_delay`, `update_grace_period`, `update_minimum_delay`, `update_maximum_delay`, `update_ethereum_governance_executor`.

If you want to execute a custom function, you can add your own task in `scripts_l1/tasks.ts`. You just need to add all the calls you want to execute.

For each call:

- The first element is a boolean (1 if it is a delegated call, 0 if a simple call).
- The second element is the target address or the target hash if it's a delegate call.
- The third element is the function selector.
- The fourth element is the size of the calldata.
- All other elements are calldata elements (be careful, for `u256`, low and high must be provided).

**Example:**
```typescript
const multicall = [];
const update_grace_period_call = [
  0,
  bridgeExecutor,
  hash.getSelector('update_grace_period'),
  1,
  parseFloat(taskArgs.param1)
];
multicall.push(update_grace_period_call);

