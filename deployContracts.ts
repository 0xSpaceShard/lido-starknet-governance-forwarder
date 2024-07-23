import { Account, byteArray, Calldata, Contract, json, RpcProvider, shortString } from "starknet";
import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config({ path: __dirname + '/../.env' })

const provider = new RpcProvider({ nodeUrl: process.env.RPC});
const owner = new Account(provider, process.env.ACCOUNT_ADDRESS as string, process.env.ACCOUNT_PK as string, "1");

async function deployBridgeExecutor(): Promise<Contract> {
    
    const compiledContract = await json.parse(fs.readFileSync(`./target/dev/lido_forward_BridgeExecutor.contract_class.json`).toString('ascii'));
    const governance_executor = '0x46c1e48B26D1B35b63B1e852CF34BEE589184557'
    const { transaction_hash, contract_address } = await owner.deploy({
        classHash: process.env.BRIDGEEXECUTOR_CLASS_HASH as string,
        constructorCalldata: {
            delay: 60,
            grace_period: 1000,
            minimum_delay: 20,
            maximum_delay: 200,
            guardian: owner.address,
            ethereum_governance_executor: governance_executor
        }
    });

    const contractAddress: any = contract_address[0];
    await provider.waitForTransaction(transaction_hash);
    const bridgeExecutor = new Contract(compiledContract.abi, contractAddress, owner);
    console.log('✅ Bridge Executor contract connected at =', bridgeExecutor.address);
    fs.appendFile(__dirname + '/../.env', `\n${'bridgeExecutor'.toUpperCase()}_ADDRESS=${contractAddress}`, function (err) {
        if (err) throw err;
    });
    return bridgeExecutor;
}


async function main() {

    const flag = process.argv[2];
    const action = process.argv[3];

    if (!flag || !action) {
        throw new Error("Missing --contract <contract_name>");
    }

    switch (action) {
        case "BridgeExecutor":
            console.log("Deploying BridgeExecutor...");
            await deployBridgeExecutor();
            break;
    
        default:
            throw new Error("Error: Unknown contract");
    }
    
}

main();