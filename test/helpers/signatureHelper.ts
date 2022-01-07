import { arrayify, solidityKeccak256 } from "ethers/lib/utils";
import { Listing, Order } from "./populator";

export function hashListing(_listing: Listing) {
  return solidityKeccak256(
    ["bytes32", "address", "uint256", "uint256", "uint256", "uint256"],
    [
      _listing.ipfsHash,
      _listing.seller,
      _listing.commissionPercentage,
      _listing.warranty,
      _listing.cashbackPercentage,
      _listing.expiration,
    ]
  ) as string;
}

export function hashOrder(_order: Order) {
  return solidityKeccak256(
    [
      "bytes32",
      "address",
      "address",
      "address",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
      "uint256",
    ],
    [
      hashListing(_order.listing),
      _order.buyer,
      _order.commissioner,
      _order.token,
      _order.quantity,
      _order.total,
      _order.cashback,
      _order.commission,
      _order.protocolFee,
      _order.confirmationTimeout,
      _order.nonce,
    ]
  ) as string;
}

export function hashToSign(_hash: string) {
  return solidityKeccak256(
    ["string", "bytes32"],
    ["\x19Ethereum Signed Message:\n32", _hash]
  ) as string;
}