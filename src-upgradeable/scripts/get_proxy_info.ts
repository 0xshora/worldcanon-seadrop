import { ethers } from "hardhat";

/**
 * Manually read EIP-1967 proxy slots
 * This is critical for security and operational transparency
 */
async function getProxyInfo(proxyAddress: string) {
  console.log("🔍 Reading EIP-1967 proxy slots for:", proxyAddress);

  // EIP-1967 standard slots
  const IMPLEMENTATION_SLOT =
    "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  const ADMIN_SLOT =
    "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  const BEACON_SLOT =
    "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50";

  try {
    // Read implementation address
    const implAddressRaw = await ethers.provider.getStorageAt(
      proxyAddress,
      IMPLEMENTATION_SLOT
    );
    const implementationAddress =
      implAddressRaw !==
      "0x0000000000000000000000000000000000000000000000000000000000000000"
        ? ethers.utils.getAddress("0x" + implAddressRaw.slice(-40))
        : null;

    // Read admin address
    const adminAddressRaw = await ethers.provider.getStorageAt(
      proxyAddress,
      ADMIN_SLOT
    );
    const adminAddress =
      adminAddressRaw !==
      "0x0000000000000000000000000000000000000000000000000000000000000000"
        ? ethers.utils.getAddress("0x" + adminAddressRaw.slice(-40))
        : null;

    // Read beacon address (for Beacon proxy)
    const beaconAddressRaw = await ethers.provider.getStorageAt(
      proxyAddress,
      BEACON_SLOT
    );
    const beaconAddress =
      beaconAddressRaw !==
      "0x0000000000000000000000000000000000000000000000000000000000000000"
        ? ethers.utils.getAddress("0x" + beaconAddressRaw.slice(-40))
        : null;

    // Determine proxy type
    let proxyType = "Unknown";
    if (implementationAddress && adminAddress) {
      proxyType = "TransparentUpgradeableProxy";
    } else if (implementationAddress && !adminAddress) {
      proxyType = "UUPSUpgradeable";
    } else if (beaconAddress) {
      proxyType = "BeaconProxy";
    }

    const result = {
      proxy: proxyAddress,
      proxyType,
      implementation: implementationAddress,
      admin: adminAddress,
      beacon: beaconAddress,
    };

    console.log("📋 Proxy Information:");
    console.log("  Type:", proxyType);
    console.log("  Proxy:", proxyAddress);
    console.log("  Implementation:", implementationAddress || "Not found");
    console.log("  Admin:", adminAddress || "Not found");
    if (beaconAddress) console.log("  Beacon:", beaconAddress);

    // Security checks
    await performSecurityChecks(result);

    return result;
  } catch (error) {
    console.error("❌ Error reading proxy information:", error);
    throw error;
  }
}

async function performSecurityChecks(proxyInfo: any) {
  console.log("\n🔒 Security Checks:");

  // Check if implementation has code
  if (proxyInfo.implementation) {
    const implCode = await ethers.provider.getCode(proxyInfo.implementation);
    console.log("  ✅ Implementation has code:", implCode !== "0x");

    if (implCode === "0x") {
      console.log("  🚨 WARNING: Implementation address has no code!");
    }
  }

  // Check if admin has code (should be ProxyAdmin contract)
  if (proxyInfo.admin) {
    const adminCode = await ethers.provider.getCode(proxyInfo.admin);
    console.log("  ✅ Admin has code:", adminCode !== "0x");

    if (adminCode === "0x") {
      console.log("  ⚠️  Admin is EOA, not ProxyAdmin contract");
    }
  }

  // Check proxy functionality
  try {
    const proxyCode = await ethers.provider.getCode(proxyInfo.proxy);
    console.log("  ✅ Proxy has code:", proxyCode !== "0x");
  } catch (e) {
    console.log("  ❌ Error checking proxy code");
  }
}

async function main() {
  // Current deployed proxy
  const DEPLOYED_PROXY = "0xdF577670A2Ab6c4bC27e4BaD80F891cA5d5C5ae0";

  const proxyInfo = await getProxyInfo(DEPLOYED_PROXY);

  // Save to deployment record
  const deploymentRecord = {
    network: "base-sepolia",
    timestamp: new Date().toISOString(),
    contracts: {
      Imprint: proxyInfo,
    },
  };

  console.log("\n💾 Saving proxy information...");
  const fs = require("fs");
  fs.writeFileSync(
    `proxy-info-${Date.now()}.json`,
    JSON.stringify(deploymentRecord, null, 2)
  );

  console.log("\n🎯 Action Items:");
  console.log("1. Verify these addresses match your expected deployment");
  console.log("2. Save admin address for future upgrades");
  console.log("3. Verify ProxyAdmin ownership/multisig setup");
  console.log("4. Document upgrade procedures");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
