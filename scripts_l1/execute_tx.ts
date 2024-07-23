import dotenv from 'dotenv';
dotenv.config({ path: __dirname + '/../.env' });
import { readConfigs } from './utils';
import starknetCoreAbi from './abi/starknetCore.json'
import { RpcProvider, hash } from 'starknet';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const bridgeExecutor = process.env.BRIDGEEXECUTOR_ADDRESS as string

export async function executeL2Multicall(hre: HardhatRuntimeEnvironment, call: Array<Array<any>>) {
    const starknetProvider = new RpcProvider({ nodeUrl: process.env.RPC});
    const [ethereum_executor] = await hre.ethers.getSigners();
    console.log("ethereum executor address:", ethereum_executor.address);
    const balance0ETH = await hre.ethers.provider.getBalance(ethereum_executor.address);
    console.log("User Balance:", hre.ethers.formatEther(balance0ETH));
    const configs = readConfigs();
    const addresses = configs[hre.network.name];
    const starknetCoreContract = new hre.ethers.Contract(addresses.starknetCore, starknetCoreAbi, ethereum_executor);

    const payload = [];
    payload.push(call.length)
    for (let index = 0; index < call.length; index++) {
      payload.push(...call[index]); 
    }
    payload.unshift(payload.length);
    const messageFromL1 = {
        from_address:ethereum_executor.address,
        to_address: bridgeExecutor,
        entry_point_selector: hash.getSelector('handle_response'),        
        payload
    }
    const l2MessagingFees = (await starknetProvider.estimateMessageFee(messageFromL1)).overall_fee
    try {
        const tx = await starknetCoreContract.sendMessageToL2(messageFromL1.to_address, messageFromL1.entry_point_selector, messageFromL1.payload, {value:l2MessagingFees});
        console.log(`Transaction hash: ${tx.hash}`);
        await tx.wait();
        console.log(`Message sent to L2; ${call}`);
    } catch (error) {
        console.error(`Error Sending message to L2: ${error}`);
    }


}
