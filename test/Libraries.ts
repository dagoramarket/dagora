import type { DagoraLib, DagoraLibTest, PercentageLib } from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { generateListing, generateOrder } from "./helpers/populator";
import { hashListing, hashOrder } from "./helpers/signatureHelper";

describe("PercentageLib", async () => {
  let percentageLib: PercentageLib;
  before(async () => {
    const PercentageLib = await ethers.getContractFactory("PercentageLib");
    percentageLib = (await PercentageLib.deploy()) as PercentageLib;
    await percentageLib.deployed();
  });

  it("calculate percentage correctly", async () => {
    const total = 1000;
    const percentage = 100; // 10%
    const result = await percentageLib.calculateTotalFromPercentage(
      total,
      percentage
    );

    const BASE = (await percentageLib.INVERSE_BASIS_POINT()).toNumber();
    const expected = Math.floor((total * percentage) / BASE);
    expect(result.toNumber()).to.be.equal(expected);
  });
});

describe("DagoraLib", async () => {
  let dagoraLibTest: DagoraLibTest;
  let seller: SignerWithAddress,
    buyer: SignerWithAddress,
    token: SignerWithAddress;
  before(async () => {
    const DagoraLib = await ethers.getContractFactory("DagoraLib");
    const dagoraLib = (await DagoraLib.deploy()) as DagoraLib;
    await dagoraLib.deployed();
    const DagoraLibTest = await ethers.getContractFactory("DagoraLibTest", {
      libraries: {
        DagoraLib: dagoraLib.address,
      },
    });
    dagoraLibTest = (await DagoraLibTest.deploy()) as DagoraLibTest;
    await dagoraLibTest.deployed();
    [, seller, buyer, token] = await ethers.getSigners();
  });

  it("hash listing", async () => {
    const listing = generateListing(seller.address);
    const result = await dagoraLibTest.hashListing(listing);

    const hash = hashListing(listing);
    expect(result).to.be.equal(hash);
  });
  it("hash order", async () => {
    const listing = generateListing(seller.address);

    const order = generateOrder(listing, buyer.address, token.address, 100);
    const result = await dagoraLibTest.hashOrder(order);

    const hash = hashOrder(order);
    expect(result).to.be.equal(hash);
  });
});
