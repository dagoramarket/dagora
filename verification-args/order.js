const listingManagerAddress = process.env.LISTING_MANAGER_ADDRESS || "";
const disputeManagerAddress = process.env.DISPUTE_MANAGER_ADDRESS || "";

const deployer = process.env.DEPLOYER_ADDRESS || "";

const PROTOCOL_FEE = 300; // 3%

module.exports = [
  listingManagerAddress,
  disputeManagerAddress,
  deployer,
  PROTOCOL_FEE,
];
