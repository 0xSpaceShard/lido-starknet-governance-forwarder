import { task } from "hardhat/config";
import dotenv from 'dotenv';
dotenv.config({ path: __dirname + '/../.env' });
import { executeL2Multicall } from "./execute_tx";
import { hash } from "starknet";

const bridgeExecutor = process.env.BRIDGEEXECUTOR_ADDRESS as string

task("update_minimum_delay", "Update minimum Delay")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_minimum_delay_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_minimum_delay'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_minimum_delay_call)
  await executeL2Multicall(hre, multicall);
  });


task("update_maximum_delay", "Update maximum delay ")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_maximum_delay_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_maximum_delay'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_maximum_delay_call)
  await executeL2Multicall(hre, multicall);
  });


task("update_ethereum_governance_executor", "Update Ethereum Governance Executor")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_ethereum_governance_executor_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_ethereum_governance_executor'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_ethereum_governance_executor_call)
  await executeL2Multicall(hre, multicall);
  });


task("update_delay", "Update Delay")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_delay_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_delay'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_delay_call)
  await executeL2Multicall(hre, multicall);
  });


task("update_guardian", "Update Guardian")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_guardian_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_guardian'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_guardian_call)
  await executeL2Multicall(hre, multicall);
  });

task("update_grace_period", "Update Grace Period")
  .addPositionalParam("param1")
  .setAction(async (taskArgs, hre) => {
    const multicall = []
    const update_grace_period_call = [
      0,
      bridgeExecutor,
      hash.getSelector('update_grace_period'),
      1,
      parseFloat(taskArgs.param1)
  ];
  multicall.push(update_grace_period_call)
  await executeL2Multicall(hre, multicall);
  });