import "@nomiclabs/hardhat-waffle";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-preprocessor";
import * as dotenv from "dotenv";
import * as path from "path";
import * as fs from "fs";

// Load .env from parent directory
dotenv.config({ path: path.resolve(__dirname, "../.env") });

// Get remappings from current directory
function getRemappings() {
  const remappingsPath = path.resolve(__dirname, "./remappings.txt");
  return fs
    .readFileSync(remappingsPath, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line: string) => line.trim().split("="));
}

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    sepolia: {
      url: process.env.ETH_SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    base: {
      url: process.env.BASE_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    "base-sepolia": {
      url: process.env.BASE_SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY,
      base: process.env.BASESCAN_API_KEY,
      "base-sepolia": process.env.BASESCAN_API_KEY,
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
      },
      {
        network: "base-sepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  preprocess: {
    eachLine: (hre: any) => ({
      transform: (line: string) => {
        if (line.match(/ from "/i)) {
          getRemappings().forEach(([find, replace]: string[]) => {
            if (line.includes(`"${find}`)) {
              line = line.replace(`"${find}`, `"${replace}`);
            }
          });
        }
        return line;
      },
    }),
  },
};
