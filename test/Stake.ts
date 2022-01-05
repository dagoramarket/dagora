import type { DagoraToken, StakeManager } from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

describe("Staking", async () => {
  let token: DagoraToken;
  let stakeManager: StakeManager;
  let owner: SignerWithAddress,
    buyer: SignerWithAddress,
    seller: SignerWithAddress;

  before(async () => {
    [owner, buyer, seller] = await ethers.getSigners();
    const StakeManager = await ethers.getContractFactory("StakeManager");
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
  context("stake()", () => {
    it("should be able to stake", async () => {
      const stakeAmount = 10;
      await token.connect(seller).approve(stakeManager.address, stakeAmount);

      const balanceBefore = await stakeManager.balance(seller.address);

      const stakeTokensTx = await stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await stakeTokensTx.wait();

      const balanceAfter = await stakeManager.balance(seller.address);

      expect(balanceAfter.toNumber() - balanceBefore.toNumber()).to.be.equal(
        stakeAmount
      );
      expect(stakeTokensTx)
        .to.emit(stakeManager, "StakeToken")
        .withArgs(seller.address, stakeAmount);
    });
    it("shouldn't be able to stake because it isn't allowed", async () => {
      const stakeAmount = 10;
      const stakeTokensTx = stakeManager
        .connect(seller)
        .stakeTokens(stakeAmount);
      await expect(stakeTokensTx).to.be.reverted;
    });
  });
  context("unstake()", () => {
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
  });

  context("lockStake()", () => {
    it("should be able to lock stake", async () => {
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
    it("shouldn't be able to lock stake not enoght balance", async () => {
      const balance = await stakeManager.balance(seller.address);

      const lockStakeTx = stakeManager.lockStake(
        seller.address,
        balance.toNumber() + 1
      );
      await expect(lockStakeTx).to.be.reverted;
    });
  });
  context("unlockStake()", () => {
    it("should be able to unlock stake", async () => {
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
    it("shouldn't be able to unlock stake because not enoght locked tokens", async () => {
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

      const unlockStakeTx = stakeManager.unlockStake(
        seller.address,
        beforeLockedTokens.toNumber() + 1
      );
      await expect(unlockStakeTx).to.be.reverted;
    });
  });
  context("burnLockedStake()", () => {
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
      const burnTx = await stakeManager.burnLockedStake(
        seller.address,
        stakeAmount
      );
      await burnTx.wait();
      const afterLockedTokens = await stakeManager.lockedTokens(seller.address);
      expect(
        beforeLockedTokens.toNumber() - afterLockedTokens.toNumber()
      ).to.be.equals(stakeAmount);
      expect(burnTx)
        .to.emit(stakeManager, "BurnLockedStake")
        .withArgs(seller.address, stakeAmount);
    });
  });
  it("non-operator shouldn't be able to use operator's methods", async () => {
    await (await stakeManager.setOperator(seller.address)).wait();
    const stakeAmount = 10;
    const lockStakeTx = stakeManager.lockStake(seller.address, stakeAmount);
    await expect(lockStakeTx).to.be.revertedWith("Only operator");
    const unlockStakeTx = stakeManager.unlockStake(seller.address, stakeAmount);
    await expect(unlockStakeTx).to.be.revertedWith("Only operator");
    const burnLockedStake = stakeManager.burnLockedStake(
      seller.address,
      stakeAmount
    );
    await expect(burnLockedStake).to.be.revertedWith("Only operator");

    await (await stakeManager.setOperator(owner.address)).wait();
  });
});
