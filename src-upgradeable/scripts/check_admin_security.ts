import { ethers } from "hardhat";

async function checkAdminSecurity() {
  const PROXY_ADMIN = "0xd634Ce48C3b9e4ca35F4AC0Fa6eBd3B3f9e97247";
  const PROXY = "0xdF577670A2Ab6c4bC27e4BaD80F891cA5d5C5ae0";
  
  console.log("🔐 Checking ProxyAdmin Security Configuration");
  console.log("ProxyAdmin:", PROXY_ADMIN);
  
  try {
    // Manual ProxyAdmin ABI for critical functions
    const ProxyAdminABI = [
      "function owner() view returns (address)",
      "function getProxyAdmin(address proxy) view returns (address)",
      "function getProxyImplementation(address proxy) view returns (address)"
    ];
    
    const ProxyAdmin = new ethers.Contract(PROXY_ADMIN, ProxyAdminABI, ethers.provider);
    
    // Check owner of ProxyAdmin
    const owner = await ProxyAdmin.owner();
    console.log("\n📋 Ownership Information:");
    console.log("  ProxyAdmin Owner:", owner);
    
    // Check if owner is EOA or contract
    const ownerCode = await ethers.provider.getCode(owner);
    const isContract = ownerCode !== "0x";
    console.log("  Owner Type:", isContract ? "Contract (Multisig/DAO)" : "EOA (Single Key)");
    
    if (!isContract) {
      console.log("  🚨 SECURITY RISK: Single key ownership!");
      console.log("  💡 Recommendation: Transfer to multisig wallet");
    } else {
      console.log("  ✅ Good: Owner is a contract");
    }
    
    // Check proxy admin relationship
    const proxyAdminFromProxy = await ProxyAdmin.getProxyAdmin(PROXY);
    console.log("\n🔗 Proxy Relationship:");
    console.log("  Proxy Admin (from proxy):", proxyAdminFromProxy);
    console.log("  Matches ProxyAdmin?", proxyAdminFromProxy.toLowerCase() === PROXY_ADMIN.toLowerCase());
    
    // Check current implementation
    const implementation = await ProxyAdmin.getProxyImplementation(PROXY);
    console.log("  Current Implementation:", implementation);
    
    // Security assessment
    console.log("\n🛡️ Security Assessment:");
    if (!isContract) {
      console.log("  ❌ HIGH RISK: Single key can upgrade contract");
      console.log("  ❌ No upgrade delay mechanism");
      console.log("  ❌ No governance/voting required");
    } else {
      console.log("  ✅ Multi-signature or governance protection");
      console.log("  ℹ️  Need to verify multisig threshold");
    }
    
    // Operational guidance
    console.log("\n📝 Operational Recommendations:");
    console.log("1. 🔐 If single key: Transfer to multisig immediately");
    console.log("2. 📚 Document upgrade procedures");
    console.log("3. 🧪 Test upgrades on testnet first");
    console.log("4. ⏱️  Consider timelock for upgrade delays");
    console.log("5. 👥 Establish governance process");
    
    // Save current state for future reference
    const securityReport = {
      timestamp: new Date().toISOString(),
      network: "base-sepolia",
      proxyAdmin: PROXY_ADMIN,
      proxy: PROXY,
      owner: owner,
      ownerType: isContract ? "contract" : "eoa",
      implementation: implementation,
      riskLevel: isContract ? "medium" : "high",
      recommendations: [
        isContract ? "Verify multisig threshold" : "Transfer to multisig",
        "Document upgrade procedures",
        "Test on testnet",
        "Consider timelock",
        "Establish governance"
      ]
    };
    
    require("fs").writeFileSync(
      `security-report-${Date.now()}.json`,
      JSON.stringify(securityReport, null, 2)
    );
    
    console.log("\n💾 Security report saved");
    
  } catch (error) {
    console.error("❌ Error checking admin security:", error);
    
    // Fallback: manual checks
    console.log("\n🔄 Performing manual security checks...");
    
    const adminCode = await ethers.provider.getCode(PROXY_ADMIN);
    console.log("ProxyAdmin has code:", adminCode !== "0x");
    
    if (adminCode === "0x") {
      console.log("🚨 CRITICAL: ProxyAdmin has no code!");
    }
  }
}

checkAdminSecurity()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });