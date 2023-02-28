import { BigNumber } from "ethers";
import { ethers } from "hardhat";

const ARBITRATION_FEE = BigNumber.from(10).pow(9); // 10 ^ 9

async function main() {
  const TestDisputeManager = await ethers.getContractFactory(
    "TestDisputeManager"
  );
  const disputeManager = await TestDisputeManager.deploy();
  await disputeManager.deployed();
  const disputeReceipt = await ethers.provider.waitForTransaction(
    disputeManager.deployTransaction.hash
  );

  console.log("Dispute Manager deployed at:", disputeReceipt.contractAddress);

  const updateArbCostTx = await disputeManager.updateArbCost(ARBITRATION_FEE);
  await updateArbCostTx.wait();

  console.log("Arbitration fee updated to ", ARBITRATION_FEE.toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
