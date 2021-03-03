function generateListing(sellerAddress) {
  return {
    ipfsHash: web3.utils.randomHex(32),
    seller: sellerAddress,
    commissionPercentage: 0,
    warranty: 0,
    cashbackPercentage: 0,
    expiration: 0,
  };
}

function generateOrder(listing, buyer, tokenAddress, timestamp = 0) {
  return {
    listing: listing,
    buyer: buyer,
    commissioner: buyer,
    token: tokenAddress,
    quantity: 1,
    total: 500,
    cashback: 0,
    commission: 0,
    protocolFee: 5,
    confirmationTimeout: 0,
    timestamp: timestamp,
  };
}

module.exports = {
  generateListing,
  generateOrder,
};
