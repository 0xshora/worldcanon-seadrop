import { ethers } from "hardhat";

async function checkProxy() {
  const proxyAddress = "0xdF577670A2Ab6c4bC27e4BaD80F891cA5d5C5ae0";
  
  console.log("Checking proxy at:", proxyAddress);
  
  // Check if contract exists
  const code = await ethers.provider.getCode(proxyAddress);
  console.log("Contract code exists:", code !== "0x");
  
  // Try to read implementation slot (EIP-1967)
  const implementationSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  try {
    const implAddressRaw = await ethers.provider.getStorageAt(proxyAddress, implementationSlot);
    const implAddress = ethers.utils.getAddress("0x" + implAddressRaw.slice(-40));
    console.log("Implementation address:", implAddress);
  } catch (e) {
    console.log("Error reading implementation:", e.message);
  }
  
  // Try to read admin slot (EIP-1967)
  const adminSlot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  try {
    const adminAddressRaw = await ethers.provider.getStorageAt(proxyAddress, adminSlot);
    const adminAddress = ethers.utils.getAddress("0x" + adminAddressRaw.slice(-40));
    console.log("Admin address:", adminAddress);
  } catch (e) {
    console.log("Error reading admin:", e.message);
  }
  
  // Try to call a function
  try {
    const Imprint = await ethers.getContractFactory("Imprint");
    const imprint = Imprint.attach(proxyAddress);
    const name = await imprint.name();
    console.log("Contract name():", name);
    console.log("✅ Proxy is functioning correctly!");
  } catch (e) {
    console.log("Error calling function:", e.message);
  }
}

checkProxy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });