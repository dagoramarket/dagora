import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DagoraToken, StakeManager } from "../../typechain";

const dgrAddress = process.env.DGR_TOKEN_ADDRESS || "";
const stakeManagerAddress = process.env.STAKE_MANAGER_ADDRESS || "";
const MINIMUM_STAKE = BigNumber.from(10000).mul(BigNumber.from(10).pow(18)); // 1000000 * 10 ^ 18

async function main() {
  const DagoraToken = await ethers.getContractFactory("DagoraToken");
  const StakeManager = await ethers.getContractFactory("StakeManager");

  const token = DagoraToken.attach(dgrAddress) as DagoraToken;

  const stakeManager = StakeManager.attach(stakeManagerAddress) as StakeManager;

  const approveTx = await token.approve(stakeManager.address, MINIMUM_STAKE);
  await approveTx.wait();

  console.log(
    MINIMUM_STAKE.toString().toString(),
    "DGR approved to address:",
    stakeManager.address,
    "tx hash:",
    approveTx.hash
  );

  const stakeTokenxTx = await stakeManager.stakeTokens(MINIMUM_STAKE);
  await stakeTokenxTx.wait();

  console.log(
    MINIMUM_STAKE.toString().toString(),
    "DGR staked",
    "tx hash:",
    stakeTokenxTx.hash
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
