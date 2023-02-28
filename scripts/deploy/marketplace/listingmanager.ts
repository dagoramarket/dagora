import { BigNumber } from "ethers";
import { ethers } from "hardhat";

const stakeManagerAddress = process.env.STAKE_MANAGER_ADDRESS || "";
const disputeManagerAddress = process.env.DISPUTE_MANAGER_ADDRESS || "";

const MINIMUM_STAKE = BigNumber.from(10000).mul(BigNumber.from(10).pow(18)); // 10000 * 10 ^ 18
const PERCENTAGE_BURN = 2000; // 20%

async function main() {
  const ListingManager = await ethers.getContractFactory("ListingManager");
  const StakeManager = await ethers.getContractFactory("StakeManager");

  const stakeManager = StakeManager.attach(stakeManagerAddress);

  const listingManager = await ListingManager.deploy(
    stakeManagerAddress,
    disputeManagerAddress,
    MINIMUM_STAKE,
    PERCENTAGE_BURN
  );

  await listingManager.deployed();
  const listingReceipt = await ethers.provider.waitForTransaction(
    listingManager.deployTransaction.hash
  );

  console.log("Listing Manager deployed at:", listingReceipt.contractAddress);

  await (await stakeManager.setOperator(listingReceipt.contractAddress)).wait();

  console.log(
    "Stake Manager operator updated to:",
    listingReceipt.contractAddress
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
