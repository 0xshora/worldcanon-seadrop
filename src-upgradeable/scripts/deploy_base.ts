import fs from "fs";
const hre = require("hardhat");
const { ethers, upgrades } = hre;

async function deployToBase() {
  console.log("Deploying to Base Sepolia testnet...");
  
  // Deploy Subject first (non-upgradeable)
  console.log("\n1. Deploying Subject...");
  const Subject = await ethers.getContractFactory("Subject");
  
  console.log("Creating Subject deployment transaction...");
  const subjectToken = await Subject.deploy("World Canon Subjects", "WCSBJ");
  
  console.log("Waiting for Subject deployment...");
  await subjectToken.deployed();
  console.log("Subject deployed to:", subjectToken.address);
  
  // トランザクションの確認を待つ
  console.log("Waiting for Subject transaction confirmation...");
  await subjectToken.deployTransaction.wait(2);
  
  // Deploy ImprintLib library first
  console.log("\n2. Deploying ImprintLib library...");
  const ImprintLib = await ethers.getContractFactory("ImprintLib");
  
  // Get current gas price for debugging
  const gasPrice = await ethers.provider.getGasPrice();
  console.log("Current gas price:", ethers.utils.formatUnits(gasPrice, "gwei"), "gwei");
  
  console.log("Creating ImprintLib deployment transaction...");
  const imprintLib = await ImprintLib.deploy();
  
  console.log("Waiting for ImprintLib deployment...");
  await imprintLib.deployed();
  console.log("ImprintLib deployed to:", imprintLib.address);
  
  // トランザクションの確認を待つ
  console.log("Waiting for ImprintLib transaction confirmation...");
  await imprintLib.deployTransaction.wait(2);

  // Deploy Imprint
  console.log("\n3. Deploying Imprint...");
  const Imprint = await ethers.getContractFactory("Imprint", {
    libraries: {
      ImprintLib: imprintLib.address,
    },
  });
  
  const imprintTokenName = "WorldCanonImprint";
  const imprintTokenSymbol = "WCIMP";
  const allowedSeaDrop = ["0x00005EA00Ac477B1030CE78506496e8C2dE24bf5"];
  
  const [deployer] = await ethers.getSigners();
  
  const imprintToken = await upgrades.deployProxy(
    Imprint,
    [
      imprintTokenName,
      imprintTokenSymbol,
      allowedSeaDrop,
      deployer.address, // initialOwner
    ],
    { 
      initializer: "initializeImprint",
      unsafeAllowLinkedLibraries: true 
    }
  );
  
  await imprintToken.deployed();
  console.log("Imprint deployed to:", imprintToken.address);
  
  // Get deployment addresses
  const subjectAddresses = {
    address: subjectToken.address,
    // Subject is not upgradeable, so no proxy/admin/implementation addresses
  };
  
  // Get proxy addresses with error handling
  let imprintAddresses;
  try {
    imprintAddresses = {
      proxy: imprintToken.address,
      admin: await upgrades.erc1967.getAdminAddress(imprintToken.address),
      implementation: await upgrades.erc1967.getImplementationAddress(
        imprintToken.address
      ),
    };
  } catch (error) {
    console.log("Warning: Could not retrieve proxy addresses, using fallback...");
    imprintAddresses = {
      proxy: imprintToken.address,
      admin: "Error retrieving admin address",
      implementation: "Error retrieving implementation address",
    };
  }
  
  const deploymentInfo = {
    network: "base-sepolia",
    timestamp: new Date().toISOString(),
    contracts: {
      Subject: subjectAddresses,
      ImprintLib: imprintLib.address,
      Imprint: imprintAddresses,
    },
    seaDrop: allowedSeaDrop[0],
  };
  
  console.log("\nDeployment Summary:");
  console.log("==================");
  console.log("Subject:", subjectAddresses);
  console.log("ImprintLib:", imprintLib.address);
  console.log("Imprint:", imprintAddresses);
  
  // Save deployment addresses
  const filename = `deployment-base-sepolia-${Date.now()}.json`;
  fs.writeFileSync(filename, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to: ${filename}`);
  
  // Verify contracts on Basescan
  console.log("\nVerifying contracts on Basescan...");
  
  try {
    console.log("Verifying Subject contract...");
    await hre.run("verify:verify", { 
      address: subjectAddresses.address,
      constructorArguments: ["World Canon Subjects", "WCSBJ"],
    });
  } catch (e) {
    console.log("Subject verification error:", e);
  }
  
  try {
    console.log("Verifying Imprint implementation...");
    await hre.run("verify:verify", { 
      address: imprintAddresses.implementation,
      constructorArguments: [],
    });
  } catch (e) {
    console.log("Imprint verification error:", e);
  }
  
  // Configure contracts
  console.log("\nConfiguring contracts...");
  
  try {
    // Set Imprint contract address in Subject
    console.log("Setting Imprint contract in Subject...");
    await subjectToken.setImprintContract(imprintToken.address);
    console.log("✓ Imprint contract set in Subject");
    
    // Set Subject contract (worldCanon) in Imprint
    console.log("Setting Subject contract in Imprint...");
    await imprintToken.setWorldCanon(subjectToken.address);
    console.log("✓ Subject contract set in Imprint");
    
  } catch (e) {
    console.log("Configuration error:", e);
  }
  
  console.log("\nDeployment complete!");
}

// Run deployment
deployToBase()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });