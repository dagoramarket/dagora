const { BigNumber } = require("ethers");

const stakeManagerAddress = process.env.STAKE_MANAGER_ADDRESS || "";
const disputeManagerAddress = process.env.DISPUTE_MANAGER_ADDRESS || "";

const MINIMUM_STAKE = BigNumber.from(10000).mul(BigNumber.from(10).pow(18)); // 10000 * 10 ^ 18
const PERCENTAGE_BURN = 2000; // 20%

module.exports = [
  stakeManagerAddress,
  disputeManagerAddress,
  MINIMUM_STAKE,
  PERCENTAGE_BURN,
];
