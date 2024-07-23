import { Account, json, RpcProvider } from 'starknet';
import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config({ path: __dirname + '/../.env' });

const provider = new RpcProvider({ nodeUrl: process.env.RPC});
const owner = new Account(provider, process.env.ACCOUNT_ADDRESS as string, process.env.ACCOUNT_PK as string, "1");

export async function declareContract(name: string) {
    const compiledContract = await json.parse(fs.readFileSync(`./target/dev/lido_forward_${name}.contract_class.json`).toString('ascii'));
    const compiledSierraCasm = await json.parse(fs.readFileSync(`./target/dev/lido_forward_${name}.compiled_contract_class.json`).toString('ascii'));
    const declareResponse = await owner.declare({
        contract: compiledContract,
        casm: compiledSierraCasm,
    });
    
    console.log('Contract classHash: ', declareResponse.class_hash);
    fs.appendFile(__dirname + '/../.env', `\n${name.toUpperCase()}_CLASS_HASH=${declareResponse.class_hash}`, function (err) {
        if (err) throw err;
    });
}

async function main() {
    

    if (!process.argv[2] || !process.argv[3]) {
        throw new Error("Missing --contract <contract_name>");
    }

    switch (process.argv[3]) {
        case "BridgeExecutor":
            await declareContract('BridgeExecutor');
            break;

        default:
            throw new Error("Error: Unknown contract");
    }
    
    
}

main();