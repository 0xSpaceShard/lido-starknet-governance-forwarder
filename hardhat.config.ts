import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import { config as dotenvConfig } from "dotenv";
import "./scripts_l1/tasks";

dotenvConfig();

const PrivateKey: string = process.env.ETH_ACCOUNT_PK || "";
const RPC: string = process.env.ETH_RPC || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: false,
    },
  },
  networks: {
    goerli: {
      url: RPC,
      accounts: [PrivateKey],
    },
    sepolia: {
      url: RPC,
      accounts: [PrivateKey],
    },
    mainnet: {
      url: RPC,
      accounts: [PrivateKey],
    },
  }
};

export default config;
