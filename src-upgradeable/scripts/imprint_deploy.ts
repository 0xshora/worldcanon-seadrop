import fs from "fs";
import { ethers, upgrades } from "hardhat";

async function mainDeploy() {
  const WorldCanonImprint = await ethers.getContractFactory(
    "WorldCanonImprint"
  );

  console.log("Deploying...");

  const tokenName = "WorldCanonImprint";
  const tokenSymbol = "WCIMP";
  const allowedSeaDrop = ["0x00005EA00Ac477B1030CE78506496e8C2dE24bf5"];

  const token = await upgrades.deployProxy(
    WorldCanonImprint,
    [tokenName, tokenSymbol, allowedSeaDrop],
    { initializer: "initialize" }
  );

  await token.deployed();

  const addresses = {
    proxy: token.address,
    admin: await upgrades.erc1967.getAdminAddress(token.address),
    implementation: await upgrades.erc1967.getImplementationAddress(
      token.address
    ),
  };
  console.log("Addresses: ", addresses);

  try {
    await (run as any)("verify", { address: addresses.implementation });
  } catch (e) {}

  fs.writeFileSync("deployment-addresses.json", JSON.stringify(addresses));
}

mainDeploy();
