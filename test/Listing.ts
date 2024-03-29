import type {
  DagoraToken,
  StakeManager,
  ListingManager,
  DisputeManager,
  TestDisputeManager,
} from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { generateListing, Listing } from "./helpers/populator";
import { hashListing, toHex } from "./helpers/signatureHelper";
import { BigNumber } from "ethers";
import { advanceBlocks, getBlock } from "./helpers/testHelper";

const MINIMUM_STAKE = 1000;
const PERCENTAGE_BURN = 1000;
describe("Listing", async () => {
  let token: DagoraToken;
  let stakeManager: StakeManager;
  let listingManager: ListingManager;
  let disputeManager: TestDisputeManager;
  let owner: SignerWithAddress,
    buyer: SignerWithAddress,
    seller: SignerWithAddress;

  let arbCost: BigNumber;

  before(async () => {
    [owner, buyer, seller] = await ethers.getSigners();

    const StakeManager = await ethers.getContractFactory("StakeManager");
    const TestDisputeManager = await ethers.getContractFactory(
      "TestDisputeManager"
    );
    const DagoraToken = await ethers.getContractFactory("DagoraToken");
    const PercentageLib = await ethers.getContractFactory("PercentageLib");
    const percentageLib = await PercentageLib.deploy();
    const DagoraLib = await ethers.getContractFactory("DagoraLib");
    const dagoraLib = await DagoraLib.deploy();
    const ListingManager = await ethers.getContractFactory("ListingManager", {
      libraries: {
        PercentageLib: percentageLib.address,
        DagoraLib: dagoraLib.address,
      },
    });

    token = (await DagoraToken.deploy()) as DagoraToken;
    await token.deployed();

    stakeManager = (await StakeManager.deploy(token.address)) as StakeManager;
    stakeManager.deployed();

    disputeManager = (await TestDisputeManager.deploy()) as TestDisputeManager;

    arbCost = await disputeManager.arbitrationCost();
    listingManager = (await ListingManager.deploy(
      stakeManager.address,
      disputeManager.address,
      MINIMUM_STAKE,
      PERCENTAGE_BURN
    )) as ListingManager;

    await (await stakeManager.setOperator(listingManager.address)).wait();
    await token.mint(owner.address, 100000);
    await token.mint(buyer.address, 100000);
    await token.mint(seller.address, 100000);

    await (
      await token
        .connect(seller)
        .approve(stakeManager.address, ethers.constants.MaxUint256)
    ).wait();

    const stakeTx = await stakeManager
      .connect(seller)
      .stakeTokens(MINIMUM_STAKE * 2);
    await stakeTx.wait();

    await (
      await token
        .connect(owner)
        .approve(stakeManager.address, ethers.constants.MaxUint256)
    ).wait();

    const stakeOwnerTx = await stakeManager
      .connect(owner)
      .stakeTokens(MINIMUM_STAKE * 2);
    await stakeOwnerTx.wait();
  });

  context("#requireValidListing()", () => {
    it("should return hash", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const listingHash = await listingManager
        .connect(seller)
        .requireValidListing(listing);

      expect(listingHash).to.be.equal(hash);
    });
    it("seller doesn't have minimum staked", async () => {
      const listing = generateListing(buyer.address);

      const listingHash = listingManager
        .connect(seller)
        .connect(seller)
        .requireValidListing(listing);

      await expect(listingHash).to.be.reverted;
    });
    it("listing cancelled", async () => {
      const listing = generateListing(seller.address);

      const cancelListingTx = await listingManager
        .connect(seller)
        .cancelListing(listing);
      await cancelListingTx.wait();

      const listingHash = listingManager.requireValidListing(listing);

      await expect(listingHash).to.be.reverted;
    });
    it("listing expired", async () => {
      const currentBlock = await getBlock();
      const listing = generateListing(
        seller.address,
        false,
        currentBlock.number + 3
      );
      await advanceBlocks(4);

      const listingHash = listingManager
        .connect(seller)
        .requireValidListing(listing);

      await expect(listingHash).to.be.reverted;
    });
    it("listing in dispute", async () => {
      const listing = generateListing(seller.address);
      const quantity = 10;

      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, quantity);
      await createListingTx.wait();

      const reportTx = await listingManager.report(listing, {
        value: arbCost,
      });
      await reportTx.wait();

      const listingHash = listingManager
        .connect(seller)
        .requireValidListing(listing);

      await expect(listingHash).to.be.reverted;
    });
  });

  context("#createListing()", () => {
    it("should create a listing", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);
      const quantity = 10;

      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, quantity);
      await createListingTx.wait();

      expect(createListingTx)
        .to.emit(listingManager, "ListingCreated")
        .withArgs(
          hash,
          listing.seller,
          listing.ipfsHash,
          listing.expirationBlock,
          listing.commissionPercentage,
          listing.cashbackPercentage,
          listing.warranty,
          quantity
        );
    });
    it("shouldn't create listing if not seller", async () => {
      const listing = generateListing(seller.address);
      const quantity = 10;

      const createListingTx = listingManager.createListing(listing, quantity);
      await expect(createListingTx).to.be.revertedWith("You must be seller");
    });
  });
  context("#updateListing()", () => {
    it("should update a listing", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);
      const quantity = 10;

      const updateListingTx = await listingManager
        .connect(seller)
        .updateListing(listing, quantity);
      await updateListingTx.wait();

      expect(updateListingTx)
        .to.emit(listingManager, "ListingUpdated")
        .withArgs(hash, quantity);
    });
    it("shouldn't update listing if not seller", async () => {
      const listing = generateListing(seller.address);
      const quantity = 10;

      const updateListingTx = listingManager.updateListing(listing, quantity);
      await expect(updateListingTx).to.be.revertedWith("You must be seller");
    });
  });
  context("#cancelListing()", () => {
    let listing: Listing;
    let hash: string;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      hash = hashListing(listing);

      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
    });

    it("should cancel a listing", async () => {
      const cancelListingTx = await listingManager
        .connect(seller)
        .cancelListing(listing);
      await cancelListingTx.wait();

      const approved = await listingManager.approvedListings(hash);

      expect(cancelListingTx)
        .to.emit(listingManager, "ListingCancelled")
        .withArgs(hash);
      expect(approved).to.be.false;
    });
    it("shouldn't cancel listing if not seller", async () => {
      const cancelListingTx = listingManager.cancelListing(listing);
      await expect(cancelListingTx).to.be.revertedWith("You must be seller");

      const approved = await listingManager.approvedListings(hash);

      expect(approved).to.be.true;
    });
  });
  context("#report()", () => {
    let listing: Listing;
    let hash: string;
    before(async () => {
      listing = generateListing(seller.address);
      hash = hashListing(listing);

      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
    });

    it("should report listing and finalize in favor of reporter", async () => {
      const balanceStake = await stakeManager.balance(seller.address);
      const tokensReported = balanceStake.mul(PERCENTAGE_BURN).div(10000);

      const beforeLockedStake = await stakeManager.lockedTokens(seller.address);

      const reportTx = await listingManager.report(listing, {
        value: arbCost,
      });
      await reportTx.wait();
      const afterLockedStake = await stakeManager.lockedTokens(seller.address);

      expect(reportTx)
        .to.emit(listingManager, "ListingReported")
        .withArgs(hash);
      expect(reportTx).to.emit(disputeManager, "HasToPayFee").withArgs(hash, 1);
      expect(afterLockedStake.sub(beforeLockedStake)).to.be.equal(
        tokensReported
      );
    });
    it("shouldn't report itself", async () => {
      const reportTx = listingManager.connect(seller).report(listing, {
        value: arbCost,
      });
      await expect(reportTx).to.be.revertedWith("You can't report yourself");
    });
    it("should revert invalid listing", async () => {
      const onDisputeTx = listingManager.onDispute(hash);
      await expect(onDisputeTx).to.be.revertedWith(
        "Only dispute manager can call this function"
      );
    });
    it("should revert only dispute manager", async () => {
      const onDisputeTx = listingManager.onDispute(hash);
      await expect(onDisputeTx).to.be.revertedWith(
        "Only dispute manager can call this function"
      );
    });
  });
  context("#rulingCallback()", () => {
    let hash: string;
    let tokensReported: BigNumber;
    beforeEach(async () => {
      const listing = generateListing(seller.address);
      hash = hashListing(listing);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();

      const balanceStake = await stakeManager.balance(seller.address);
      tokensReported = balanceStake.mul(PERCENTAGE_BURN).div(10000);
      const reportTx = await listingManager.report(listing, {
        value: arbCost,
      });
      await reportTx.wait();
      const payArbitrationFee = await disputeManager
        .connect(seller)
        .payArbitrationFee(hash, {
          value: arbCost,
        });
      await payArbitrationFee.wait();
    });
    it("should finalize in favor of reporter", async () => {
      const balanceBeforeRule = await stakeManager.balance(seller.address);

      const ruleTx = await disputeManager.rule(hash, 1);
      await ruleTx.wait();

      const balanceAfterRule = await stakeManager.balance(seller.address);

      expect(balanceBeforeRule.sub(balanceAfterRule)).to.be.equal(
        tokensReported
      );
      expect(ruleTx)
        .to.emit(stakeManager, "BurnLockedStake")
        .withArgs(seller.address, tokensReported);
      expect(ruleTx)
        .to.emit(listingManager, "ListingReportResult")
        .withArgs(hash, 1);
    });
    it("should finalize in favor of seller", async () => {
      const balanceBeforeRule = await stakeManager.balance(seller.address);
      const lockedTokensBeforeRule = await stakeManager.lockedTokens(
        seller.address
      );

      const ruleTx = await disputeManager.rule(hash, 2);
      await ruleTx.wait();

      const balanceAfterRule = await stakeManager.balance(seller.address);
      const lockedTokensAfterRule = await stakeManager.lockedTokens(
        seller.address
      );

      expect(balanceBeforeRule).to.be.equal(balanceAfterRule);
      expect(lockedTokensBeforeRule.sub(lockedTokensAfterRule)).to.be.equal(
        tokensReported
      );
      expect(ruleTx)
        .to.emit(stakeManager, "UnlockStake")
        .withArgs(seller.address, tokensReported);
      expect(ruleTx)
        .to.emit(listingManager, "ListingReportResult")
        .withArgs(hash, 2);
    });
    it("should finalize in favor of neither", async () => {
      const balanceBeforeRule = await stakeManager.balance(seller.address);
      const lockedTokensBeforeRule = await stakeManager.lockedTokens(
        seller.address
      );

      const ruleTx = await disputeManager.rule(hash, 0);
      await ruleTx.wait();

      const balanceAfterRule = await stakeManager.balance(seller.address);
      const lockedTokensAfterRule = await stakeManager.lockedTokens(
        seller.address
      );

      const half = tokensReported.div(2);
      expect(balanceBeforeRule.sub(balanceAfterRule)).to.be.equal(half);
      expect(lockedTokensBeforeRule.sub(lockedTokensAfterRule)).to.be.equal(
        tokensReported
      );
      expect(ruleTx)
        .to.emit(stakeManager, "UnlockStake")
        .withArgs(seller.address, half);
      expect(ruleTx)
        .to.emit(stakeManager, "BurnLockedStake")
        .withArgs(seller.address, half);
      expect(ruleTx)
        .to.emit(listingManager, "ListingReportResult")
        .withArgs(hash, 0);
    });
  });
});
