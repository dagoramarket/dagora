import type {
  DagoraToken,
  DisputeManager,
  TestDisputable,
  TestDisputeManager,
} from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { advanceTimeAndBlock } from "./helpers/testHelper";
import { BigNumber } from "ethers";
import { generateRandomHash } from "./helpers/populator";
import { toHex } from "./helpers/signatureHelper";
import { parseUnits } from "ethers/lib/utils";

const ARB_COST = 1000;
const DISPUTE_TIMEOUT = 60 * 60 * 24 * 7; // 7 days

describe("Dispute", async () => {
  let token: DagoraToken;
  let disputeManager: TestDisputeManager;
  let disputable: TestDisputable;
  let owner: SignerWithAddress,
    prosecution: SignerWithAddress,
    defendant: SignerWithAddress;

  let arbCost: BigNumber;

  before(async () => {
    [owner, prosecution, defendant] = await ethers.getSigners();

    const TestDisputeManager = await ethers.getContractFactory(
      "TestDisputeManager"
    );
    const TestDisputable = await ethers.getContractFactory("TestDisputable");
    const DagoraToken = await ethers.getContractFactory("DagoraToken");
    token = (await DagoraToken.deploy()) as DagoraToken;
    await token.deployed();

    disputeManager = (await TestDisputeManager.deploy()) as TestDisputeManager;

    const updateArbTx = await disputeManager.updateArbCost(ARB_COST);
    await updateArbTx.wait();

    const updateTimeoutTx = await disputeManager.updateDisputeTimeout(
      DISPUTE_TIMEOUT
    );
    await updateTimeoutTx.wait();

    arbCost = await disputeManager.arbitrationCost();

    disputable = (await TestDisputable.deploy(
      disputeManager.address
    )) as TestDisputable;

    await token.mint(owner.address, 100000);
    await token.mint(prosecution.address, 100000);
    await token.mint(defendant.address, 100000);

    const approveProsecutionTx = await token
      .connect(prosecution)
      .approve(disputable.address, ethers.constants.MaxUint256);
    await approveProsecutionTx.wait();
    const approveDefendantTx = await token
      .connect(defendant)
      .approve(disputable.address, ethers.constants.MaxUint256);
    await approveDefendantTx.wait();
  });

  context("createDispute()", () => {
    it("should wait for other party fee", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const beforeBalanceContract = await token.balanceOf(disputable.address);

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const dispute = await disputeManager.disputes(hash);
      const afterBalanceContract = await token.balanceOf(disputable.address);
      expect(afterBalanceContract.sub(beforeBalanceContract)).to.eq(
        totalValue * 2
      );
      expect(dispute.prosecution).to.be.eq(prosecution.address);
      expect(dispute.defendant).to.be.eq(defendant.address);
      expect(dispute.token).to.be.eq(token.address);
      expect(dispute.amount).to.be.eq(totalValue);
      expect(dispute.disputable).to.be.eq(disputable.address);
      expect(dispute.prosecutionFee).to.be.eq(arbCost);
      expect(dispute.defendantFee).to.be.eq(0);
      expect(dispute.status).to.be.eq(2);

      expect(createDisputeTx)
        .to.emit(disputeManager, "HasToPayFee")
        .withArgs(toHex(hash), 1);
    });
    it("shouldn't create dispute fee doesn't cover arb cost", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost.sub(1),
          }
        );
      await expect(createDisputeTx).to.be.revertedWith(
        "The fee must cover arbitration costs."
      );
    });
    it("shouldn't create dispute because already created", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const createDisputeTx2 = disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await expect(createDisputeTx2).to.be.reverted;
    });
  });
  context("disputeTimeout()", () => {
    it("should execute ruling timeout for prosecution", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const balanceProsecutionBefore = await token.balanceOf(
        prosecution.address
      );
      const balanceDefendantBefore = await token.balanceOf(defendant.address);

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      await advanceTimeAndBlock(DISPUTE_TIMEOUT + 1);

      const disputeTimeoutTx = await disputeManager.disputeTimeout(hash);
      await disputeTimeoutTx.wait();

      const dispute = await disputeManager.disputes(hash);

      const balanceProsecutionAfter = await token.balanceOf(
        prosecution.address
      );
      const balanceDefendantAfter = await token.balanceOf(defendant.address);

      expect(dispute.status).to.be.eq(4); // Status Resolved
      expect(balanceProsecutionAfter.sub(balanceProsecutionBefore)).to.eq(
        totalValue
      );
      expect(balanceDefendantAfter.sub(balanceDefendantBefore)).to.eq(
        -totalValue
      );
    });
    it("should execute ruling timeout for defendant", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const balanceProsecutionBefore = await token.balanceOf(
        prosecution.address
      );
      const balanceDefendantBefore = await token.balanceOf(defendant.address);

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const updateArbCostTx = await disputeManager.updateArbCost(ARB_COST + 1);
      await updateArbCostTx.wait();

      const payArbitrationFeeTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: ARB_COST + 1,
        });
      await payArbitrationFeeTx.wait();

      await advanceTimeAndBlock(DISPUTE_TIMEOUT + 1);

      const disputeTimeoutTx = await disputeManager.disputeTimeout(hash);
      await disputeTimeoutTx.wait();

      const dispute = await disputeManager.disputes(hash);

      const balanceProsecutionAfter = await token.balanceOf(
        prosecution.address
      );
      const balanceDefendantAfter = await token.balanceOf(defendant.address);

      expect(dispute.status).to.be.eq(4); // Status Resolved
      expect(balanceProsecutionAfter.sub(balanceProsecutionBefore)).to.eq(
        -totalValue
      );
      expect(balanceDefendantAfter.sub(balanceDefendantBefore)).to.eq(
        totalValue
      );
      const updateArbCostTx2 = await disputeManager.updateArbCost(ARB_COST);
      await updateArbCostTx2.wait();
    });
    it("time didn't expired yet", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const disputeTimeoutTx = disputeManager.disputeTimeout(hash);
      await expect(disputeTimeoutTx).to.be.revertedWith(
        "Timeout time has not passed yet."
      );
    });
    it("dispute doesn't exists", async () => {
      const hash = generateRandomHash();

      const disputeTimeoutTx = disputeManager.disputeTimeout(hash);
      await expect(disputeTimeoutTx).to.be.revertedWith(
        "Dispute is not waiting for any party."
      );
    });
  });

  context("payArbitrationFee()", () => {
    it("should raise dispute with defendant paying", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const payArbitrationFeeTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost,
        });
      await payArbitrationFeeTx.wait();

      const dispute = await disputeManager.disputes(hash);

      expect(dispute.status).to.be.eq(3); // Status DisputeCreated
      expect(dispute.defendantFee).to.be.eq(arbCost);

      expect(payArbitrationFeeTx)
        .emit(disputeManager, "DisputeCreated")
        .withArgs(toHex(hash));
    });
    it("should raise dispute with prosecution paying", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const updateArbCostTx = await disputeManager.updateArbCost(ARB_COST + 1);
      await updateArbCostTx.wait();

      const payArbitrationFeeDefendantTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: ARB_COST + 1,
        });
      await payArbitrationFeeDefendantTx.wait();

      const payArbitrationFeeProsecutionTx = await disputeManager
        .connect(prosecution)
        .payArbitrationFee(hash, {
          value: 1,
        });
      await payArbitrationFeeProsecutionTx.wait();

      const dispute = await disputeManager.disputes(hash);

      expect(dispute.status).to.be.eq(3); // Status DisputeCreated

      expect(payArbitrationFeeProsecutionTx)
        .emit(disputeManager, "DisputeCreated")
        .withArgs(toHex(hash));

      const updateArbCostTx2 = await disputeManager.updateArbCost(ARB_COST);
      await updateArbCostTx2.wait();
    });
    it("dispute already created", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const payArbitrationFeeTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost,
        });
      await payArbitrationFeeTx.wait();

      const payArbitrationFeeTx2 = disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost,
        });
      await expect(payArbitrationFeeTx2).to.be.revertedWith(
        "Dispute has already been created."
      );
    });
    it("must cover arbitration costs", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const payArbitrationFeeTx = disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost.sub(1),
        });
      await expect(payArbitrationFeeTx).to.be.revertedWith(
        "The fee must cover arbitration costs."
      );
    });
    it("must be party", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const anotherSigner = (await ethers.getSigners())[3];

      const payArbitrationFeeTx = disputeManager
        .connect(anotherSigner)
        .payArbitrationFee(hash, {
          value: arbCost,
        });
      await expect(payArbitrationFeeTx).to.be.revertedWith("Must be party");
    });
  });

  context("raiseDispute()", () => {
    it("should refund overpaid fee", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost.add(10),
          }
        );
      await createDisputeTx.wait();

      const prosecutionBalance = await prosecution.getBalance();
      const defendantBalance = await defendant.getBalance();

      const payArbitrationFeeTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost.add(11),
        });

      const receipt = await payArbitrationFeeTx.wait();
      const etherSpent = receipt.effectiveGasPrice.mul(receipt.gasUsed);

      const prosecutionBalance2 = await prosecution.getBalance();
      const defendantBalance2 = await defendant.getBalance();

      expect(prosecutionBalance2.sub(prosecutionBalance)).to.be.eq(10);
      expect(defendantBalance.sub(defendantBalance2).sub(etherSpent)).to.be.eq(
        arbCost
      );
    });
  });

  context("rule()", () => {
    it("should rule even", async () => {
      const hash = generateRandomHash();
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();

      const payArbitrationFeeTx = await disputeManager
        .connect(defendant)
        .payArbitrationFee(hash, {
          value: arbCost,
        });

      await payArbitrationFeeTx.wait();

      const prosecutionBalance = await prosecution.getBalance();
      const defendantBalance = await defendant.getBalance();

      const beforeBalanceContract = await token.balanceOf(disputable.address);
      const beforeBalanceProsecution = await token.balanceOf(
        prosecution.address
      );
      const beforeBalanceDefendant = await token.balanceOf(defendant.address);

      const ruleTx = await disputeManager.rule(hash, 0);
      await ruleTx.wait();

      const afterBalanceContract = await token.balanceOf(disputable.address);

      const afterBalanceProsecution = await token.balanceOf(
        prosecution.address
      );
      const afterBalanceDefendant = await token.balanceOf(defendant.address);

      const prosecutionBalance2 = await prosecution.getBalance();
      const defendantBalance2 = await defendant.getBalance();
      expect(afterBalanceContract.sub(beforeBalanceContract)).to.eq(
        -2 * totalValue
      );
      expect(afterBalanceProsecution.sub(beforeBalanceProsecution)).to.eq(
        totalValue
      );
      expect(afterBalanceDefendant.sub(beforeBalanceDefendant)).to.eq(
        totalValue
      );

      expect(prosecutionBalance2.sub(prosecutionBalance)).to.be.eq(
        arbCost.div(2)
      );
      expect(defendantBalance2.sub(defendantBalance)).to.be.eq(arbCost.div(2));
    });
  });
  context("TestDisputeManager coverage", () => {
    let hash: string;
    before(async () => {
      hash = toHex(generateRandomHash());
      const totalValue = 100;

      const createDisputeTx = await disputable
        .connect(prosecution)
        .createDispute(
          hash,
          prosecution.address,
          defendant.address,
          token.address,
          totalValue,
          {
            value: arbCost,
          }
        );
      await createDisputeTx.wait();
    });
    it("submitEvidence()", async () => {
      const data = "testing";
      const submitEvidenceTx = await disputeManager
        .connect(prosecution)
        .submitEvidence(hash, data);
      await submitEvidenceTx.wait();

      expect(submitEvidenceTx)
        .to.emit(disputeManager, "Evidence")
        .withArgs(hash, prosecution.address, data);
    });
    it("appeal()", async () => {
      const appealTx = await disputeManager.connect(prosecution).appeal(hash);
      await appealTx.wait();

      expect(appealTx)
        .to.emit(disputeManager, "Appeal")
        .withArgs(hash, prosecution.address);
    });
  });
});
