import { ethers } from "hardhat";

export async function advanceTimeAndBlock(time: number) {
  await advanceTime(time);
  await advanceBlock();

  return await ethers.provider.getBlock("latest");
}

export async function advanceTime(time: number) {
  await ethers.provider.send("evm_increaseTime", [time]);
}

export async function advanceBlock() {
  await ethers.provider.send("evm_mine", []);
}
