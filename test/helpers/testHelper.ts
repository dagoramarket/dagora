import { ethers } from "hardhat";

export async function advanceBlocks(n: number) {
  for (let i = 0; i < n; i++) {
    await advanceBlock();
  }

  return await getBlock();
}

export async function advanceTimeAndBlock(time: number) {
  await advanceTime(time);
  await advanceBlock();

  return await getBlock();
}

export async function getBlock() {
  return await ethers.provider.getBlock("latest");
}

export async function advanceTime(time: number) {
  await ethers.provider.send("evm_increaseTime", [time]);
}

export async function advanceBlock() {
  await ethers.provider.send("evm_mine", []);
}
