import type { DagoraToken, StakeManager } from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

describe("Dagora", async () => {
  context("Staking", () => {
    let token: DagoraToken;
    let stakeManager: StakeManager;
    let owner: SignerWithAddress,
      buyer: SignerWithAddress,
      seller: SignerWithAddress;

    before(async () => {
      [owner, buyer, seller] = await ethers.getSigners();

      const PercentageLib = await ethers.getContractFactory("PercentageLib");
      const percentageLib = await PercentageLib.deploy();
      const StakeManager = await ethers.getContractFactory("StakeManager", {
        libraries: {
          PercentageLib: percentageLib.address,
        },
      });
      const DagoraToken = await ethers.getContractFactory("DagoraToken");
      token = (await DagoraToken.deploy()) as DagoraToken;
      await token.deployed();

      stakeManager = (await StakeManager.deploy(token.address)) as StakeManager;
      stakeManager.deployed();

      await (await stakeManager.setOperator(owner.address)).wait();
      await token.mint(owner.address, 100000);
      await token.mint(buyer.address, 100000);
      await token.mint(seller.address, 100000);
    });

    it("should be able to stake", async () => {
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const balance = await stakeManager.balance(seller.address);

      expect(balance.toNumber()).to.be.equal(stakeAmount);
      expect(stakeTokensTx)
        .to.emit(stakeManager, "StakeToken")
        .withArgs(seller.address, stakeAmount);
    });
    it("should be able to unstake", async () => {
      const balanceBefore = await stakeManager.balance(seller.address);
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const unstakeTokensTx = await stakeManager
        .connect(seller)
        .unstakeTokens(stakeAmount);
      await unstakeTokensTx.wait();

      const balanceAfter = await stakeManager.balance(seller.address);

      expect(balanceAfter.toNumber()).to.be.equal(balanceBefore.toNumber());
      expect(unstakeTokensTx)
        .to.emit(stakeManager, "UnstakeToken")
        .withArgs(seller.address, stakeAmount);
    });
    it("shouldn't be able to stake because it isn't allowed", async () => {
      const stakeAmount = 10;
      const stakeTokensTx = stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await expect(stakeTokensTx).to.be.reverted;
    });
    it("shouldn't be able to unstake because passes total staked value", async () => {
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const balance = await stakeManager.balance(seller.address);

      const unstakeTokensTx = stakeManager
        .connect(seller)
        .unstakeTokens(balance.toNumber() + 1);
      await expect(unstakeTokensTx).to.be.revertedWith(
        "You don't have enoght tokens"
      );
    });
    it("operator should be able to lock stake", async () => {
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const lockStakeTx = await stakeManager.lockStake(
        seller.address,
        stakeAmount
      );
      await lockStakeTx.wait();

      const lockedTokens = await stakeManager.lockedTokens(seller.address);

      expect(lockedTokens.toNumber()).to.be.equals(stakeAmount);
      expect(lockStakeTx)
        .to.emit(stakeManager, "LockStake")
        .withArgs(seller.address, stakeAmount);
    });
    it("operator should be able to unlock stake", async () => {
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const lockStakeTx = await stakeManager.lockStake(
        seller.address,
        stakeAmount
      );
      await lockStakeTx.wait();

      const beforeLockedTokens = await stakeManager.lockedTokens(
        seller.address
      );

      const unlockStakeTx = await stakeManager.unlockStake(
        seller.address,
        stakeAmount
      );
      await unlockStakeTx.wait();

      const afterLockedTokens = await stakeManager.lockedTokens(seller.address);

      expect(
        beforeLockedTokens.toNumber() - afterLockedTokens.toNumber()
      ).to.be.equals(stakeAmount);
      expect(unlockStakeTx)
        .to.emit(stakeManager, "UnlockStake")
        .withArgs(seller.address, stakeAmount);
    });
    it("should burn locked stake", async () => {
      const stakeAmount = 100;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);
      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const lockStakeTx = await stakeManager.lockStake(
        seller.address,
        stakeAmount
      );
      await lockStakeTx.wait();

      const beforeLockedTokens = await stakeManager.lockedTokens(
        seller.address
      );
      const percentage = 1000; // 10%
      const burnTx = await stakeManager.burnLockedStake(
        seller.address,
        percentage
      );
      await burnTx.wait();
      const afterLockedTokens = await stakeManager.lockedTokens(seller.address);

      const expectedAmount = Math.floor(
        (beforeLockedTokens.toNumber() * percentage) / 10000
      );
      expect(
        beforeLockedTokens.toNumber() - afterLockedTokens.toNumber()
      ).to.be.equals(expectedAmount);
      expect(burnTx)
        .to.emit(stakeManager, "BurnLockedStake")
        .withArgs(seller.address, expectedAmount);
    });
  });
});
