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

const MINIMUM_STAKE = 1000;
const PERCENTAGE_BURN = 1000;
describe("Listing", async () => {
  let token: DagoraToken;
  let stakeManager: StakeManager;
  let listingManager: ListingManager;
  let owner: SignerWithAddress,
    buyer: SignerWithAddress,
    seller: SignerWithAddress;

  before(async () => {
    [owner, buyer, seller] = await ethers.getSigners();

    const StakeManager = await ethers.getContractFactory("StakeManager");
    // const DisputeLib = await ethers.getContractFactory("DisputeLib");
    // const disputeLib = await DisputeLib.deploy();
    const TestDisputeManager = await ethers.getContractFactory(
      "TestDisputeManager",
      {
        // libraries: {
        //   DisputeLib: disputeLib.address,
        // },
      }
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

    const disputeManager =
      (await TestDisputeManager.deploy()) as DisputeManager;

    listingManager = (await ListingManager.deploy(
      stakeManager.address,
      disputeManager.address,
      MINIMUM_STAKE,
      PERCENTAGE_BURN
    )) as ListingManager;

    await (await stakeManager.setOperator(owner.address)).wait();
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
  });
});
