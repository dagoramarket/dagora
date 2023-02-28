import { ethers } from "hardhat";
import { DagoraToken } from "../../../typechain";

async function main() {
  // const [deployer] = await ethers.getSigners();

  const DagoraToken = await ethers.getContractFactory("DagoraToken");

  const token = (await DagoraToken.deploy()) as DagoraToken;
  await token.deployed();

  const txHash = token.deployTransaction.hash;
  const txReceipt = await ethers.provider.waitForTransaction(txHash);

  console.log(
    "Dagora Token (DGR) deployed to:",
    txReceipt.contractAddress,
    "Tx hash:",
    txHash
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
