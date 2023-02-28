import { ethers } from "hardhat";

const listingManagerAddress = process.env.LISTING_MANAGER_ADDRESS || "";
const disputeManagerAddress = process.env.DISPUTE_MANAGER_ADDRESS || "";

const PROTOCOL_FEE = 300; // 3%

async function main() {
  const [deployer] = await ethers.getSigners();

  const OrderManager = await ethers.getContractFactory("OrderManager");

  const orderManager = await OrderManager.deploy(
    listingManagerAddress,
    disputeManagerAddress,
    deployer.address,
    PROTOCOL_FEE
  );
  await orderManager.deployed();

  const orderReceipt = await ethers.provider.waitForTransaction(
    orderManager.deployTransaction.hash
  );

  console.log("Order Manager deployed at:", orderReceipt.contractAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
