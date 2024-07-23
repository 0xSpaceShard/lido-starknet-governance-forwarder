import { Account, byteArray, Calldata, Contract, json, RpcProvider, shortString } from "starknet";
import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config({ path: __dirname + '/../.env' })

const provider = new RpcProvider({ nodeUrl: process.env.RPC});
const owner = new Account(provider, process.env.ACCOUNT_ADDRESS as string, process.env.ACCOUNT_PK as string, "1");

async function cancel(action_id: number) {
    const compiledContract = await json.parse(fs.readFileSync(`./target/dev/lido_forward_BridgeExecutor.contract_class.json`).toString('ascii'));
    const bridgeExecutorContract = new Contract(compiledContract.abi, process.env.BRIDGEEXECUTOR_ADDRESS as string, owner);
    const tx = await bridgeExecutorContract.cancel(action_id);
    console.log(tx);
    // await provider.waitForTransaction(tx)
    // console.log()
}

async function main() {
    const flag = process.argv[2];
    const action_id = process.argv[3];
    if (!flag || !action_id) {
        throw new Error("Missing --action_id <action_id>");
    }
    await cancel(parseFloat(action_id));
}

main();