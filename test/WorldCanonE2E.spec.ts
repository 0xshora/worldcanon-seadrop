import { expect } from "chai";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { randomHex } from "./utils/encoding";
import { faucet } from "./utils/faucet";
import { VERSION } from "./utils/helpers";

import type { 
  Imprint, 
  Subject, 
  ImprintViews, 
  ImprintDescriptor,
  ISeaDrop,
  TransparentUpgradeableProxy,
  ProxyAdmin
} from "../typechain-types";

/**
 * World Canon E2E Test Suite
 * 
 * 完全なライフサイクルテストをHardhat/TypeScriptで実装
 * Foundryテストとの重複を避けつつ、より複雑なシナリオをテスト
 */
describe(`World Canon E2E (v${VERSION})`, function () {
  const { provider } = ethers;

  // Contract instances
  let seadrop: ISeaDrop;
  let subject: Subject;
  let imprint: Imprint;
  let imprintViews: ImprintViews;
  let imprintDescriptor: ImprintDescriptor;
  let proxyAdmin: ProxyAdmin;

  // Test actors
  let deployer: SignerWithAddress;
  let curator: SignerWithAddress;
  let collector1: SignerWithAddress;
  let collector2: SignerWithAddress;
  let collector3: SignerWithAddress;
  let researcher: SignerWithAddress;

  // Test data
  const initialSubjects = [
    "Happiness", "Sorrow", "Justice", "Freedom", "Love",
    "Fear", "Hope", "Memory", "Time", "Space",
    "Identity", "Truth", "Beauty", "Power", "Knowledge"
  ];

  before(async () => {
    // Get signers
    [deployer, curator, collector1, collector2, collector3, researcher] = 
      await ethers.getSigners();

    console.log("🚀 Setting up World Canon E2E Test Environment...");

    // Deploy SeaDrop
    const SeaDrop = await ethers.getContractFactory("SeaDrop", deployer);
    seadrop = await SeaDrop.deploy();
    await seadrop.deployed();

    // Deploy Subject (immutable)
    const Subject = await ethers.getContractFactory("Subject", deployer);
    subject = await Subject.deploy("World Canon Subjects", "WCSBJ");
    await subject.deployed();

    // Deploy ProxyAdmin
    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", deployer);
    proxyAdmin = await ProxyAdmin.deploy();
    await proxyAdmin.deployed();

    // Deploy Imprint implementation
    const Imprint = await ethers.getContractFactory("Imprint", deployer);
    const imprintImpl = await Imprint.deploy();
    await imprintImpl.deployed();

    // Deploy proxy
    const TransparentUpgradeableProxy = await ethers.getContractFactory(
      "TransparentUpgradeableProxy", 
      deployer
    );
    
    const initData = imprintImpl.interface.encodeFunctionData(
      "initializeImprint",
      [
        "WorldCanonImprint",
        "WCIMP", 
        [seadrop.address],
        curator.address
      ]
    );

    const proxy = await TransparentUpgradeableProxy.deploy(
      imprintImpl.address,
      proxyAdmin.address,
      initData
    );
    await proxy.deployed();

    imprint = Imprint.attach(proxy.address);

    // Deploy helper contracts
    const ImprintViews = await ethers.getContractFactory("ImprintViews", deployer);
    imprintViews = await ImprintViews.deploy(imprint.address);
    await imprintViews.deployed();

    const ImprintDescriptor = await ethers.getContractFactory("ImprintDescriptor", deployer);
    imprintDescriptor = await ImprintDescriptor.deploy(imprint.address);
    await imprintDescriptor.deployed();

    console.log("✅ Contract deployment completed");
  });

  beforeEach(async () => {
    // Setup for each test
    await network.provider.request({
      method: "hardhat_reset",
    });
  });

  /**
   * 🌍 Complete Marketplace Integration E2E Test
   * 
   * Foundryでは困難な外部統合テストをTypeScriptで実装
   * - OpenSea互換性
   * - メタデータ標準準拠
   * - ウォレット表示テスト
   */
  describe("🌍 Marketplace Integration", function () {
    beforeEach(async () => {
      // Basic setup for marketplace tests
      await subject.connect(curator).mintInitial(initialSubjects);
      
      await imprint.connect(curator).setDescriptor(imprintDescriptor.address);
      await imprint.connect(curator).setMaxSupply(10000);
      await imprint.connect(curator).setWorldCanon(subject.address);

      // Create edition and seeds
      await imprint.connect(curator).createEdition(1, "GPT-4o");
      
      const seeds = initialSubjects.map((name, index) => ({
        editionNo: 1,
        localIndex: index + 1,
        subjectId: index,
        subjectName: name,
        desc: `GPT-4o perspective on ${name}: An AI's interpretation of this fundamental concept.`
      }));

      await imprint.connect(curator).addSeeds(seeds);
      await imprint.connect(curator).sealEdition(1);
      await imprint.connect(curator).setActiveEdition(1);

      // Setup SeaDrop
      const publicDrop = {
        mintPrice: ethers.utils.parseEther("0.01"),
        startTime: Math.floor(Date.now() / 1000),
        endTime: Math.floor(Date.now() / 1000) + 86400 * 7, // 7 days
        maxTotalMintableByWallet: 25,
        feeBps: 250, // 2.5%
        restrictFeeRecipients: false
      };

      await imprint.connect(curator).updatePublicDrop(seadrop.address, publicDrop);
      await imprint.connect(curator).updateCreatorPayoutAddress(seadrop.address, curator.address);
    });

    it("Should generate OpenSea-compatible metadata", async () => {
      console.log("🎨 Testing OpenSea metadata compatibility...");

      // Mint NFT
      await seadrop.connect(collector1).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        1,
        { value: ethers.utils.parseEther("0.01") }
      );

      // Test Imprint metadata
      const imprintTokenURI = await imprint.tokenURI(1);
      expect(imprintTokenURI).to.match(/^data:application\/json;base64,/);

      // Decode and validate JSON structure
      const base64Data = imprintTokenURI.replace("data:application/json;base64,", "");
      const jsonData = JSON.parse(Buffer.from(base64Data, "base64").toString());

      expect(jsonData).to.have.property("name");
      expect(jsonData).to.have.property("description");
      expect(jsonData).to.have.property("image");
      expect(jsonData).to.have.property("attributes");
      expect(jsonData.image).to.match(/^data:image\/svg\+xml;base64,/);

      // Test Subject metadata (should reflect latest Imprint)
      const subjectTokenURI = await subject.tokenURI(0);
      expect(subjectTokenURI).to.not.be.empty;

      console.log("✅ OpenSea metadata compatibility verified");
    });

    it("Should handle batch minting efficiently", async () => {
      console.log("⚡ Testing batch minting efficiency...");

      const batchSize = 10;
      const mintPrice = ethers.utils.parseEther("0.01").mul(batchSize);

      const gasEstimate = await seadrop.connect(collector1).estimateGas.mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        batchSize,
        { value: mintPrice }
      );

      console.log(`Estimated gas for ${batchSize} mint: ${gasEstimate.toString()}`);

      // Execute batch mint
      const tx = await seadrop.connect(collector1).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        batchSize,
        { value: mintPrice }
      );

      const receipt = await tx.wait();
      console.log(`Actual gas used: ${receipt.gasUsed?.toString()}`);

      // Verify all tokens were minted
      expect(await imprint.balanceOf(collector1.address)).to.equal(batchSize);
      expect(await imprint.totalSupply()).to.equal(batchSize);

      console.log("✅ Batch minting efficiency verified");
    });
  });

  /**
   * 💰 Revenue and Economics E2E Test
   * 
   * 経済モデルと収益分配の包括的テスト
   */
  describe("💰 Revenue and Economics", function () {
    beforeEach(async () => {
      // Setup basic edition
      await subject.connect(curator).mintInitial(initialSubjects.slice(0, 5));
      await imprint.connect(curator).setDescriptor(imprintDescriptor.address);
      await imprint.connect(curator).setMaxSupply(1000);
      await imprint.connect(curator).setWorldCanon(subject.address);

      await imprint.connect(curator).createEdition(1, "GPT-4o");
      
      const seeds = initialSubjects.slice(0, 5).map((name, index) => ({
        editionNo: 1,
        localIndex: index + 1,
        subjectId: index,
        subjectName: name,
        desc: `Description for ${name}`
      }));

      await imprint.connect(curator).addSeeds(seeds);
      await imprint.connect(curator).sealEdition(1);
      await imprint.connect(curator).setActiveEdition(1);

      const publicDrop = {
        mintPrice: ethers.utils.parseEther("0.1"), // Higher price for revenue test
        startTime: Math.floor(Date.now() / 1000),
        endTime: Math.floor(Date.now() / 1000) + 86400,
        maxTotalMintableByWallet: 25,
        feeBps: 500, // 5% fee
        restrictFeeRecipients: false
      };

      await imprint.connect(curator).updatePublicDrop(seadrop.address, publicDrop);
      await imprint.connect(curator).updateCreatorPayoutAddress(seadrop.address, curator.address);
      await imprint.connect(curator).updateAllowedFeeRecipient(seadrop.address, curator.address, true);
    });

    it("Should correctly distribute revenue with fees", async () => {
      console.log("💸 Testing revenue distribution...");

      const mintQuantity = 3;
      const mintPrice = ethers.utils.parseEther("0.1");
      const totalValue = mintPrice.mul(mintQuantity);
      const feePercentage = 500; // 5%
      const expectedFee = totalValue.mul(feePercentage).div(10000);
      const expectedCreatorRevenue = totalValue.sub(expectedFee);

      // Record initial balances
      const initialCuratorBalance = await curator.getBalance();
      const initialSeaDropBalance = await provider.getBalance(seadrop.address);

      // Execute mint with fee
      const tx = await seadrop.connect(collector1).mintPublic(
        imprint.address,
        curator.address, // fee recipient
        curator.address, // creator
        mintQuantity,
        { value: totalValue }
      );

      await tx.wait();

      // Verify revenue distribution
      const finalCuratorBalance = await curator.getBalance();
      const finalSeaDropBalance = await provider.getBalance(seadrop.address);

      const curatorGain = finalCuratorBalance.sub(initialCuratorBalance);
      const seaDropGain = finalSeaDropBalance.sub(initialSeaDropBalance);

      console.log(`Expected creator revenue: ${ethers.utils.formatEther(expectedCreatorRevenue)} ETH`);
      console.log(`Actual curator gain: ${ethers.utils.formatEther(curatorGain)} ETH`);
      console.log(`Expected fee: ${ethers.utils.formatEther(expectedFee)} ETH`);
      console.log(`SeaDrop balance change: ${ethers.utils.formatEther(seaDropGain)} ETH`);

      // Allow for small rounding differences
      expect(curatorGain).to.be.closeTo(expectedCreatorRevenue, ethers.utils.parseEther("0.001"));

      console.log("✅ Revenue distribution verified");
    });

    it("Should handle sold out scenarios gracefully", async () => {
      console.log("🔥 Testing sold out scenarios...");

      // Mint all available tokens (5 seeds = 5 tokens max)
      const maxMintable = 5;
      const mintPrice = ethers.utils.parseEther("0.1");

      // Collector1 mints all available
      await seadrop.connect(collector1).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        maxMintable,
        { value: mintPrice.mul(maxMintable) }
      );

      expect(await imprint.totalSupply()).to.equal(maxMintable);
      expect(await imprintViews.remainingInEdition(1)).to.equal(0);

      // Collector2 tries to mint (should fail)
      await expect(
        seadrop.connect(collector2).mintPublic(
          imprint.address,
          curator.address,
          curator.address,
          1,
          { value: mintPrice }
        )
      ).to.be.revertedWith("SoldOut");

      console.log("✅ Sold out scenario handled correctly");
    });
  });

  /**
   * 🔄 Temporal Evolution E2E Test
   * 
   * 時間経過による進化とEdition切替のテスト
   */
  describe("🔄 Temporal Evolution", function () {
    it("Should simulate multi-generation AI evolution", async () => {
      console.log("🧬 Testing multi-generation AI evolution...");

      // Setup initial subjects
      await subject.connect(curator).mintInitial(initialSubjects.slice(0, 3));
      await imprint.connect(curator).setDescriptor(imprintDescriptor.address);
      await imprint.connect(curator).setMaxSupply(1000);
      await imprint.connect(curator).setWorldCanon(subject.address);

      // Generation 1: GPT-4o Era
      console.log("📅 Era 1: GPT-4o Generation");
      await imprint.connect(curator).createEdition(1, "GPT-4o");
      
      const gptSeeds = initialSubjects.slice(0, 3).map((name, index) => ({
        editionNo: 1,
        localIndex: index + 1,
        subjectId: index,
        subjectName: name,
        desc: `GPT-4o interpretation: ${name} represents the fundamental human quest for meaning.`
      }));

      await imprint.connect(curator).addSeeds(gptSeeds);
      await imprint.connect(curator).sealEdition(1);
      await imprint.connect(curator).setActiveEdition(1);

      // Setup SeaDrop
      const publicDrop = {
        mintPrice: ethers.utils.parseEther("0.01"),
        startTime: Math.floor(Date.now() / 1000),
        endTime: Math.floor(Date.now() / 1000) + 86400,
        maxTotalMintableByWallet: 25,
        feeBps: 250,
        restrictFeeRecipients: false
      };

      await imprint.connect(curator).updatePublicDrop(seadrop.address, publicDrop);
      await imprint.connect(curator).updateCreatorPayoutAddress(seadrop.address, curator.address);

      // Mint from GPT-4o generation
      await seadrop.connect(collector1).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        2,
        { value: ethers.utils.parseEther("0.02") }
      );

      expect(await imprint.totalSupply()).to.equal(2);

      // Fast forward time (simulate temporal progression)
      await network.provider.send("evm_increaseTime", [86400 * 30]); // 30 days
      await network.provider.send("evm_mine");

      // Generation 2: Claude-3.7 Era
      console.log("📅 Era 2: Claude-3.7 Generation");
      await imprint.connect(curator).createEdition(2, "Claude-3.7");
      
      const claudeSeeds = initialSubjects.slice(0, 3).map((name, index) => ({
        editionNo: 2,
        localIndex: index + 1,
        subjectId: index,
        subjectName: name,
        desc: `Claude-3.7 interpretation: ${name} embodies the constitutional principles of beneficial AI alignment.`
      }));

      await imprint.connect(curator).addSeeds(claudeSeeds);
      await imprint.connect(curator).sealEdition(2);
      await imprint.connect(curator).setActiveEdition(2);

      // Mint from Claude-3.7 generation
      await seadrop.connect(collector2).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        2,
        { value: ethers.utils.parseEther("0.02") }
      );

      expect(await imprint.totalSupply()).to.equal(4);

      // Generation 3: Future AI Era
      console.log("📅 Era 3: Future AI Generation");
      await network.provider.send("evm_increaseTime", [86400 * 365]); // 1 year
      await network.provider.send("evm_mine");

      await imprint.connect(curator).createEdition(3, "NextGen-AI-2026");
      
      const futureSeeds = initialSubjects.slice(0, 3).map((name, index) => ({
        editionNo: 3,
        localIndex: index + 1,
        subjectId: index,
        subjectName: name,
        desc: `NextGen-AI-2026 interpretation: ${name} transcends current paradigms of understanding.`
      }));

      await imprint.connect(curator).addSeeds(futureSeeds);
      await imprint.connect(curator).sealEdition(3);
      await imprint.connect(curator).setActiveEdition(3);

      // Mint from future generation
      await seadrop.connect(collector3).mintPublic(
        imprint.address,
        curator.address,
        curator.address,
        1,
        { value: ethers.utils.parseEther("0.01") }
      );

      expect(await imprint.totalSupply()).to.equal(5);

      // Verify temporal evolution - Subject should reflect latest generation
      const [, latestImprintId] = await subject.subjectMeta(0);
      expect(latestImprintId).to.equal(5); // Latest minted token

      // Verify all generations coexist
      const tokenMeta1 = await imprintViews.getTokenMeta(1);
      const tokenMeta3 = await imprintViews.getTokenMeta(3);
      const tokenMeta5 = await imprintViews.getTokenMeta(5);

      expect(tokenMeta1.model).to.equal("GPT-4o");
      expect(tokenMeta3.model).to.equal("Claude-3.7");
      expect(tokenMeta5.model).to.equal("NextGen-AI-2026");

      console.log("✅ Multi-generation AI evolution simulated successfully");
    });
  });

  after(async () => {
    console.log("🧹 Cleaning up test environment...");
    await network.provider.request({
      method: "hardhat_reset",
    });
  });
});