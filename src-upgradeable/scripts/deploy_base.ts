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
      // IMPORTANT: This flag is necessary because:
      // 1. Without libraries, contract size exceeds 24KB limit (27KB)
      // 2. Libraries reduce deployment cost and gas usage
      // 3. Manual compatibility check required during upgrades
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
  
  // Get proxy addresses with retry logic
  let imprintAddresses;
  
  // Wait a bit more for proxy deployment to be fully confirmed
  console.log("Waiting for proxy deployment to be fully confirmed...");
  await new Promise(resolve => setTimeout(resolve, 5000));
  
  let retryCount = 0;
  const maxRetries = 3;
  
  while (retryCount < maxRetries) {
    try {
      console.log(`Attempting to retrieve proxy addresses (attempt ${retryCount + 1}/${maxRetries})...`);
      imprintAddresses = {
        proxy: imprintToken.address,
        admin: await upgrades.erc1967.getAdminAddress(imprintToken.address),
        implementation: await upgrades.erc1967.getImplementationAddress(
          imprintToken.address
        ),
      };
      console.log("✓ Successfully retrieved proxy addresses");
      break;
    } catch (error) {
      retryCount++;
      if (retryCount >= maxRetries) {
        console.log("Warning: Could not retrieve proxy addresses after retries, using fallback...");
        imprintAddresses = {
          proxy: imprintToken.address,
          admin: "Error retrieving admin address",
          implementation: "Error retrieving implementation address",
        };
      } else {
        console.log(`Retry ${retryCount} failed, waiting 3 seconds...`);
        await new Promise(resolve => setTimeout(resolve, 3000));
      }
    }
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
  
  // Verify contracts on Basescan (if API key is available)
  if (process.env.BASESCAN_API_KEY && process.env.BASESCAN_API_KEY !== 'your-basescan-api-key') {
    console.log("\nVerifying contracts on Basescan...");
    
    try {
      console.log("Verifying Subject contract...");
      await hre.run("verify:verify", { 
        address: subjectAddresses.address,
        constructorArguments: ["World Canon Subjects", "WCSBJ"],
      });
      console.log("✓ Subject verification completed");
    } catch (e) {
      console.log("Subject verification error:", e.message || e);
    }
    
    if (imprintAddresses.implementation && !imprintAddresses.implementation.includes("Error")) {
      try {
        console.log("Verifying Imprint implementation...");
        await hre.run("verify:verify", { 
          address: imprintAddresses.implementation,
          constructorArguments: [],
        });
        console.log("✓ Imprint verification completed");
      } catch (e) {
        console.log("Imprint verification error:", e.message || e);
      }
    } else {
      console.log("Skipping Imprint verification (implementation address not available)");
    }
  } else {
    console.log("\nSkipping Basescan verification (BASESCAN_API_KEY not set)");
    console.log("To enable verification, set BASESCAN_API_KEY in your .env file");
    console.log("Get your API key from: https://basescan.org/apis");
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
  
  console.log("\n🎉 Deployment complete!");
  console.log("\n📝 Important Notes:");
  console.log("- Subject contract: Non-upgradeable (immutable)");
  console.log("- Imprint contract: Upgradeable via Transparent Proxy");
  console.log("- Libraries: Linked with unsafeAllowLinkedLibraries=true");
  console.log("- Upgrade Safety: Manual verification required for library compatibility");
  console.log("\n🔗 Deployed Contracts:");
  console.log(`Subject: https://sepolia.basescan.org/address/${subjectAddresses.address}`);
  console.log(`Imprint Proxy: https://sepolia.basescan.org/address/${imprintAddresses.proxy}`);
  if (imprintAddresses.implementation && !imprintAddresses.implementation.includes("Error")) {
    console.log(`Imprint Implementation: https://sepolia.basescan.org/address/${imprintAddresses.implementation}`);
  }
  console.log(`ImprintLib: https://sepolia.basescan.org/address/${imprintLib.address}`);
}

// Run deployment
deployToBase()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });