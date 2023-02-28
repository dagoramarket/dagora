import { ethers } from "hardhat";

const dgrAddress = process.env.DGR_TOKEN_ADDRESS || "";

async function main() {
  const StakeManager = await ethers.getContractFactory("StakeManager");

  const stakeManager = await StakeManager.deploy(dgrAddress);
  await stakeManager.deployed();
  const stakeReceipt = await ethers.provider.waitForTransaction(
    stakeManager.deployTransaction.hash
  );

  console.log("Stake Manager deployed at:", stakeReceipt.contractAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
