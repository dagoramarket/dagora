// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import {
  DagoraToken,
  ListingManager,
  OrderManager,
  StakeManager,
  TestDisputeManager,
} from "../typechain";

const dgrAddress = process.env.DGR_TOKEN_ADDRESS || "";
const ARBITRATION_FEE = parseEther(formatUnits(1, "gwei").toString()); // 10 ^ 9
const MINIMUM_STAKE = parseEther(formatUnits(10000, "ether").toString()); // 10000 * 10 ^ 18
const PERCENTAGE_BURN = 2000; // 20%
const PROTOCOL_FEE = 300; // 3%

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  const [deployer] = await ethers.getSigners();

  // We get the contract to deploy
  const StakeManager = await ethers.getContractFactory("StakeManager");
  const TestDisputeManager = await ethers.getContractFactory(
    "TestDisputeManager"
  );
  const DagoraToken = await ethers.getContractFactory("DagoraToken");
  const PercentageLib = await ethers.getContractFactory("PercentageLib");
  const percentageLib = await PercentageLib.deploy();
  const DagoraLib = await ethers.getContractFactory("DagoraLib");
  const dagoraLib = await DagoraLib.deploy();
  const ListingManager = await ethers.getContractFactory("ListingManager", {
    libraries: {
      PercentageLib: percentageLib.address,
      DagoraLib: dagoraLib.address,
    },
  });
  const OrderManager = await ethers.getContractFactory("OrderManager", {
    libraries: {
      PercentageLib: percentageLib.address,
      DagoraLib: dagoraLib.address,
    },
  });

  const token = DagoraToken.attach(dgrAddress) as DagoraToken;

  const stakeManager = (await StakeManager.deploy(
    token.address
  )) as StakeManager;
  stakeManager.deployed();

  console.log("Stake Manager deployed at:", stakeManager.address);

  const disputeManager =
    (await TestDisputeManager.deploy()) as TestDisputeManager;
  await disputeManager.deployed();

  console.log("Dispute Manager deployed at:", disputeManager.address);

  const updateArbCostTx = await disputeManager.updateArbCost(ARBITRATION_FEE);
  await updateArbCostTx.wait();

  console.log("Arbitration fee updated to ", ARBITRATION_FEE.toString());

  const listingManager = (await ListingManager.deploy(
    stakeManager.address,
    disputeManager.address,
    MINIMUM_STAKE,
    PERCENTAGE_BURN
  )) as ListingManager;

  await listingManager.deployed();

  console.log("Listing Manager deployed at:", listingManager.address);

  await (await stakeManager.setOperator(listingManager.address)).wait();

  console.log("Stake Manager operator updated to:", stakeManager.address);

  const orderManager = (await OrderManager.deploy(
    listingManager.address,
    disputeManager.address,
    deployer.address,
    PROTOCOL_FEE
  )) as OrderManager;
  await orderManager.deployed();

  console.log("Order Manager deployed at:", orderManager.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
