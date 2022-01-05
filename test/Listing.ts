import type { DagoraToken, StakeManager, ListingManager } from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

describe("Listing", async () => {
  let token: DagoraToken;
  let stakeManager: StakeManager;
  let listingManager: ListingManager;
  let owner: SignerWithAddress,
    buyer: SignerWithAddress,
    seller: SignerWithAddress;

  before(async () => {
    [owner, buyer, seller] = await ethers.getSigners();

    const PercentageLib = await ethers.getContractFactory("PercentageLib");
    const percentageLib = await PercentageLib.deploy();
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
});
