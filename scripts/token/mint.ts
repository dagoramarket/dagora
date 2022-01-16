import { BigNumber } from "ethers";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { DagoraToken } from "../../typechain";

const dgrAddress = process.env.DGR_TOKEN_ADDRESS || "";
const MINIMUM_STAKE = BigNumber.from("1000000").mul(BigNumber.from(10).pow(18)); // 1000000 * 10 ^ 18

async function main() {
  const [deployer] = await ethers.getSigners();

  const DagoraToken = await ethers.getContractFactory("DagoraToken");

  const token = DagoraToken.attach(dgrAddress) as DagoraToken;

  const mintTx = await token.mint(deployer.address, MINIMUM_STAKE);
  await mintTx.wait();

  console.log(
    "DGR minted",
    MINIMUM_STAKE.toString().toString(),
    "tx hash:",
    mintTx.hash
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
