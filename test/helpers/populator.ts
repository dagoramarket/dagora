import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";

export type Listing = {
  ipfsHash: string;
  seller: string;
  commissionPercentage: number;
  warranty: number;
  cashbackPercentage: number;
  expiration: BigNumber;
};

export type Order = {
  listing: Listing;
  buyer: string;
  commissioner: string;
  token: string;
  total: number;
  cashback: number;
  commission: number;
  protocolFee: number;
  confirmationTimeout: number;
  nonce: number;
};

export function generateListing(
  sellerAddress: string,
  warranty: boolean = false,
  expiration: number = 0
): Listing {
  return {
    ipfsHash: generateRandomHash().toString(),
    seller: sellerAddress,
    commissionPercentage: (Math.floor(Math.random() * 10) + 1) * 50,
    warranty: warranty ? Math.floor(Math.random() * 7) + 1 : 0,
    cashbackPercentage: (Math.floor(Math.random() * 10) + 1) * 50,
    expiration:
      expiration > 0
        ? BigNumber.from(
            Math.floor(new Date().getTime() / 1000) + expiration * 86400
          )
        : ethers.constants.MaxUint256, // Days
  };
}

export function generateOrder(
  listing: Listing,
  buyer: string,
  tokenAddress: string,
  protocol_percentage: number,
  nonce = 0,
  timeout = true,
  commissioner = ethers.constants.AddressZero
): Order {
  const price = Math.floor(Math.random() * 1000) + 1000;
  return {
    listing: listing,
    buyer: buyer,
    commissioner: commissioner,
    token: tokenAddress,
    total: price,
    cashback: Math.floor((listing.cashbackPercentage * price) / 10000),
    commission:
      commissioner != ethers.constants.AddressZero
        ? Math.floor((price * listing.commissionPercentage) / 10000)
        : 0,
    protocolFee: Math.floor((price * protocol_percentage) / 10000),
    confirmationTimeout: timeout ? Math.floor(Math.random() * 30) + 1 : 0,
    nonce: nonce,
  };
}

export function generateRandomHash(): Uint8Array {
  return ethers.utils.randomBytes(32);
}
