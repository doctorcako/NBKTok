import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";
import 'hardhat-docgen';

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: 'EUR'
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    sepolia: {
      url: process.env.BASE_SEPOLIA_TEST_NET_RCP_URL || "",
      accounts: process.env.METAMASK_PRIV_KEY ? [process.env.METAMASK_PRIV_KEY] : [],
    },
    amoy: {
      url: process.env.AMOY_TESTNET_RPC_URL || "",
      accounts: process.env.METAMASK_PRIV_KEY ? [process.env.METAMASK_PRIV_KEY] : [],
    }
  },
  mocha: {
    require: ['ts-node/register', 'test/setup.ts'],
    timeout: 40000,
    reporter: 'spec',
    reporterOptions: {
      colors: true
    }
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_API_KEY || "", // API Key de Polygonscan
    },
  },
  
};

export default config;
