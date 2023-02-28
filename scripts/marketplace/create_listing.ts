import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { ListingManager } from "../../typechain";
import { create } from "ipfs-http-client";
import { readFileSync } from "fs";

const listingManagerAddress = process.env.LISTING_MANAGER_ADDRESS || "";
const percentageLibAddress = process.env.PERCENTAGE_LIB_ADDRESS || "";
const dagoraLibAddress = process.env.PERCENTAGE_LIB_ADDRESS || "";
const MINIMUM_STAKE = BigNumber.from(10000).mul(BigNumber.from(10).pow(18)); // 1000000 * 10 ^ 18
const BLOCK_TIME = 3; // 3 seconds

async function main() {
  const ListingManager = await ethers.getContractFactory("ListingManager", {
    libraries: {
      PercentageLib: percentageLibAddress,
      DagoraLib: dagoraLibAddress,
    },
  });

  const listingManager = ListingManager.attach(
    listingManagerAddress
  ) as ListingManager;
  const [deployer] = await ethers.getSigners();
  console.log(process.env.IPFS_API_KEY);
  const client = create({
    host: "ipfs.infura.io",
    port: 5001,
    protocol: "https",
    headers: {
      Authorization: `Basic ${process.env.IPFS_API_KEY}`,
    },
  });
  const thegraph = create({
    host: "api.thegraph.com",
    port: 443,
    apiPath: "/ipfs/api/v0",
    protocol: "https",
    // headers: {
    //   Authorization: `Basic ${process.env.IPFS_API_KEY}`,
    // },
  });

  const file = await client.add({
    path: "./ps4-image.png",
    content: readFileSync("./scripts/marketplace/images/ps4-image.png"),
  });

  console.log(file);

  const listingIpfs = await client.add({
    content: readFileSync("./scripts/marketplace/listing.json"),
  });
  console.log(listingIpfs);

  const catListing = client.cat(listingIpfs.cid);

  await thegraph.add(catListing);

  const blockNumber = await ethers.provider.getBlockNumber();
  const blocks = Math.floor((60 * 60 * 24 * 30) / BLOCK_TIME); // 30 days in blocks

  const listing = {
    ipfsHash: listingIpfs.path,
    seller: deployer.address,
    commissionPercentage: 0, // 0%
    warranty: 0,
    cashbackPercentage: 100, // 1%
    expirationBlock: BigNumber.from(blockNumber + blocks),
  };

  const createListingTx = await listingManager.createListing(listing, 1);
  await createListingTx.wait();

  console.log(
    "Listing created",
    createListingTx.raw,
    "tx hash:",
    createListingTx.hash
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
