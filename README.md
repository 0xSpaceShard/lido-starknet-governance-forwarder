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

TBD
