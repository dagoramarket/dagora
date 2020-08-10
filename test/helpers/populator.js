function generateListing(sellerAddress) {
  return {
    ipfsHash: web3.utils.randomHex(32),
    seller: sellerAddress,
    stakeOwner: sellerAddress,
    stakedAmount: 10,
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
    fundsHolder: buyer,
    commissioner: buyer,
    token: tokenAddress,
    total: 500,
    cashback: 0,
    commission: 0,
    protocolFee: 1,
    stakeHolderFee: 0,
    expiration: 0,
    confirmationTimeout: 0,
    timestamp: timestamp,
  };
}

module.exports = {
  generateListing,
  generateOrder,
};
