import type {
  DagoraToken,
  StakeManager,
  ListingManager,
  DisputeManager,
} from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { generateListing } from "./helpers/populator";
import { hashListing } from "./helpers/signatureHelper";
import { advanceTimeAndBlock } from "./helpers/testHelper";
import { BigNumber } from "ethers";

const MINIMUM_STAKE = 1000;
const PERCENTAGE_BURN = 1000;
describe("Listing", async () => {
  let token: DagoraToken;
  let stakeManager: StakeManager;
  let listingManager: ListingManager;
  let disputeManager: DisputeManager;
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

    disputeManager = (await TestDisputeManager.deploy()) as DisputeManager;

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
      .stakeTokens(MINIMUM_STAKE);
    await stakeTx.wait();
  });

  context("requireValidListing()", () => {
    it("should return hash", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const listingHash = await listingManager.requireValidListing(listing);

      expect(listingHash).to.be.equal(hash);
    });
    it("seller doesn't have minimum staked", async () => {
      const listing = generateListing(buyer.address);

      const listingHash = listingManager.requireValidListing(listing);

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
      const listing = generateListing(seller.address, false, 3);
      await advanceTimeAndBlock(4 * 86400);

      const listingHash = listingManager.requireValidListing(listing);

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

      const listingHash = listingManager.requireValidListing(listing);

      await expect(listingHash).to.be.reverted;
    });
  });

  context("createListing()", () => {
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
          "0x" + Buffer.from(listing.ipfsHash).toString("hex"),
          listing.expiration,
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
  context("updateListing()", () => {
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
  context("cancelListing()", () => {
    it("should cancel a listing", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const cancelListingTx = await listingManager
        .connect(seller)
        .cancelListing(listing);
      await cancelListingTx.wait();

      const cancelled = await listingManager.cancelledListings(hash);

      expect(cancelListingTx)
        .to.emit(listingManager, "ListingCancelled")
        .withArgs(hash);
      expect(cancelled).to.be.true;
    });
    it("shouldn't cancel listing if not seller", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const cancelListingTx = listingManager.cancelListing(listing);
      await expect(cancelListingTx).to.be.revertedWith("You must be seller");

      const cancelled = await listingManager.cancelledListings(hash);

      expect(cancelled).to.be.false;
    });
  });
  context("report()", () => {
    it("should report listing", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);
      const balanceStake = await stakeManager.balance(seller.address);

      const beforeLockedStake = await stakeManager.lockedTokens(seller.address);

      const reportTx = await listingManager.report(listing, {
        value: arbCost,
      });
      await reportTx.wait();
      const afterLockedStake = await stakeManager.lockedTokens(seller.address);

      expect(reportTx).to.emit(disputeManager, "HasToPayFee").withArgs(hash, 1);
      expect(afterLockedStake.sub(beforeLockedStake)).to.be.equal(
        balanceStake.mul(PERCENTAGE_BURN).div(10000)
      );
    });
    it("shouldn't report itself", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const reportTx = listingManager.connect(seller).report(listing, {
        value: arbCost,
      });
      await expect(reportTx).to.be.revertedWith("You can't report yourself");
    });
  });
  context("onlyDisputeManager()", () => {
    it("should revert only dispute manager", async () => {
      const listing = generateListing(seller.address);
      const hash = hashListing(listing);

      const onDisputeTx = listingManager.onDispute(hash);
      await expect(onDisputeTx).to.be.revertedWith(
        "Only dispute manager can call this function"
      );
    });
  });
});
