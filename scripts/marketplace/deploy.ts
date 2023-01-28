// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { BigNumber } from "ethers";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import {
  ListingManager,
  OrderManager,
  StakeManager,
  TestDisputeManager,
} from "../../typechain";

const dgrAddress = process.env.DGR_TOKEN_ADDRESS || "";
const ARBITRATION_FEE = BigNumber.from(10).pow(9); // 10 ^ 9
const MINIMUM_STAKE = BigNumber.from(10000).mul(BigNumber.from(10).pow(18)); // 10000 * 10 ^ 18
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
  const PercentageLib = await ethers.getContractFactory("PercentageLib");
  const percentageLib = await PercentageLib.deploy();
  const percentageLibReceipt = await ethers.provider.waitForTransaction(
    percentageLib.deployTransaction.hash
  );
  console.log(
    "Percentage Lib deployed at:",
    percentageLibReceipt.contractAddress
  );
  const DagoraLib = await ethers.getContractFactory("DagoraLib");
  const dagoraLib = await DagoraLib.deploy();
  await dagoraLib.deployed();
  const dagoraLibReceipt = await ethers.provider.waitForTransaction(
    dagoraLib.deployTransaction.hash
  );
  console.log("Dagora Lib deployed at:", dagoraLibReceipt.contractAddress);
  const ListingManager = await ethers.getContractFactory("ListingManager", {
    libraries: {
      PercentageLib: percentageLibReceipt.contractAddress,
      DagoraLib: dagoraLibReceipt.contractAddress,
    },
  });
  const OrderManager = await ethers.getContractFactory("OrderManager", {
    libraries: {
      PercentageLib: percentageLibReceipt.contractAddress,
      DagoraLib: dagoraLibReceipt.contractAddress,
    },
  });

  const stakeManager = (await StakeManager.deploy(dgrAddress)) as StakeManager;
  await stakeManager.deployed();
  const stakeReceipt = await ethers.provider.waitForTransaction(
    stakeManager.deployTransaction.hash
  );

  console.log("Stake Manager deployed at:", stakeReceipt.contractAddress);

  const disputeManager =
    (await TestDisputeManager.deploy()) as TestDisputeManager;
  await disputeManager.deployed();
  const disputeReceipt = await ethers.provider.waitForTransaction(
    disputeManager.deployTransaction.hash
  );

  console.log("Dispute Manager deployed at:", disputeReceipt.contractAddress);

  const updateArbCostTx = await disputeManager.updateArbCost(ARBITRATION_FEE);
  await updateArbCostTx.wait();

  console.log("Arbitration fee updated to ", ARBITRATION_FEE.toString());

  const listingManager = (await ListingManager.deploy(
    stakeReceipt.contractAddress,
    disputeReceipt.contractAddress,
    MINIMUM_STAKE,
    PERCENTAGE_BURN
  )) as ListingManager;

  await listingManager.deployed();
  const listingReceipt = await ethers.provider.waitForTransaction(
    listingManager.deployTransaction.hash
  );

  console.log("Listing Manager deployed at:", listingReceipt.contractAddress);

  await (await stakeManager.setOperator(listingReceipt.contractAddress)).wait();

  console.log(
    "Stake Manager operator updated to:",
    stakeReceipt.contractAddress
  );

  const orderManager = (await OrderManager.deploy(
    listingReceipt.contractAddress,
    disputeReceipt.contractAddress,
    deployer.address,
    PROTOCOL_FEE
  )) as OrderManager;
  await orderManager.deployed();

  const orderReceipt = await ethers.provider.waitForTransaction(
    orderManager.deployTransaction.hash
  );

  console.log("Order Manager deployed at:", orderReceipt.contractAddress);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
