import { ethers } from "hardhat";
import { DagoraToken } from "../typechain";

async function main() {
  // const [deployer] = await ethers.getSigners();

  const DagoraToken = await ethers.getContractFactory("DagoraToken");

  const token = (await DagoraToken.deploy()) as DagoraToken;
  await token.deployed();

  console.log("Dagora Token (DGR) deployed to:", token.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
