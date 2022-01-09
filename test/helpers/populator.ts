import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";

export type Listing = {
  ipfsHash: Uint8Array;
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
  quantity: number;
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
    ipfsHash: ethers.utils.randomBytes(32),
    seller: sellerAddress,
    commissionPercentage: Math.floor(Math.random() * 10) * 10,
    warranty: warranty ? Math.floor(Math.random() * 7) + 1 : 0,
    cashbackPercentage: Math.floor(Math.random() * 10) * 10,
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
  timeout = false
): Order {
  const price = Math.floor(Math.random() * 1000);
  return {
    listing: listing,
    buyer: buyer,
    commissioner: buyer,
    token: tokenAddress,
    quantity: Math.floor(Math.random() * 5) + 1,
    total: price,
    cashback: Math.floor((listing.cashbackPercentage * price) / 10000),
    commission: Math.floor((price * listing.commissionPercentage) / 10000),
    protocolFee: Math.floor((price * protocol_percentage) / 10000),
    confirmationTimeout: timeout ? Math.floor(Math.random() * 30) + 1 : 0,
    nonce: nonce,
  };
}
