import { ethers } from "hardhat";

/**
 * CRITICAL: Transfer ProxyAdmin ownership to multisig
 * Current: Single EOA (HIGH RISK)
 * Target: Multisig wallet (MEDIUM RISK)
 */
async function transferProxyAdminOwnership() {
  const PROXY_ADMIN = "0xd634Ce48C3b9e4ca35F4AC0Fa6eBd3B3f9e97247";
  const CURRENT_OWNER = "0x7c1c866C2207208c509Ceac179Ea7C3865ecc3EF";

  console.log("🚨 CRITICAL SECURITY OPERATION");
  console.log("Transferring ProxyAdmin ownership from single key to multisig");
  console.log("Current Owner:", CURRENT_OWNER);

  // Recommended multisig wallets for Base Sepolia:
  const RECOMMENDED_MULTISIGS = {
    "gnosis-safe": "Create via https://app.safe.global",
    "existing-multisig": "Use existing team multisig",
    timelock: "Deploy TimelockController for delayed upgrades",
  };

  console.log("\n📋 Recommended Options:");
  Object.entries(RECOMMENDED_MULTISIGS).forEach(([type, info]) => {
    console.log(`  ${type}: ${info}`);
  });

  // For now, show the transfer function call
  // DO NOT EXECUTE WITHOUT PROPER MULTISIG SETUP
  console.log("\n⚠️  TO TRANSFER OWNERSHIP:");
  console.log("1. Deploy/setup multisig wallet");
  console.log("2. Verify multisig configuration");
  console.log("3. Execute transfer with current owner key");
  console.log("4. Verify transfer successful");

  const ProxyAdminABI = [
    "function owner() view returns (address)",
    "function transferOwnership(address newOwner) external",
  ];

  // Example transfer call (commented for safety)
  console.log("\n🔧 Transfer Command (DO NOT EXECUTE YET):");
  console.log(`
    // 1. Setup new multisig wallet
    const NEW_MULTISIG = "0x..."; // Your multisig address
    
    // 2. Connect with current owner
    const proxyAdmin = new ethers.Contract("${PROXY_ADMIN}", ProxyAdminABI, currentOwnerSigner);
    
    // 3. Transfer ownership
    const tx = await proxyAdmin.transferOwnership(NEW_MULTISIG);
    await tx.wait();
    
    // 4. Verify
    const newOwner = await proxyAdmin.owner();
    console.log("New owner:", newOwner);
  `);

  // Immediate risk mitigation
  console.log("\n🛡️ IMMEDIATE RISK MITIGATION:");
  console.log("1. 🔐 Secure current private key (hardware wallet/vault)");
  console.log("2. 🚫 Do NOT perform any upgrades until multisig setup");
  console.log("3. 📋 Document current deployment state");
  console.log("4. 🏗️  Setup multisig ASAP");
  console.log("5. 📝 Plan upgrade procedures");

  // Save current state for audit trail
  const ownershipReport = {
    timestamp: new Date().toISOString(),
    network: "base-sepolia",
    proxyAdmin: PROXY_ADMIN,
    currentOwner: CURRENT_OWNER,
    riskLevel: "HIGH",
    status: "REQUIRES_IMMEDIATE_ACTION",
    recommendations: [
      "Transfer to multisig immediately",
      "Secure current private key",
      "No upgrades until multisig setup",
      "Document procedures",
    ],
  };

  require("fs").writeFileSync(
    `ownership-audit-${Date.now()}.json`,
    JSON.stringify(ownershipReport, null, 2)
  );

  console.log("\n💾 Ownership audit report saved");
  console.log("🚨 ACTION REQUIRED: Setup multisig before any operations");
}

transferProxyAdminOwnership()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
