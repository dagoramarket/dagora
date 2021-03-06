function generateListing(sellerAddress) {
  return {
    ipfsHash: web3.utils.randomHex(32),
    seller: sellerAddress,
    commissionPercentage: Math.floor(Math.random() * 10) * 10,
    warranty: 0, //Math.floor(Math.random() * 7),
    cashbackPercentage: Math.floor(Math.random() * 10) * 10,
    expiration:
      Math.random() < 0.5
        ? -1
        : Math.floor(new Date().getTime() / 1000) +
          (Math.floor(Math.random() * 29) + 1) * 86400, // Days
  };
}

function generateOrder(
  listing,
  buyer,
  tokenAddress,
  protocol_percentage,
  timestamp = 0
) {
  price = Math.floor(Math.random() * 1000);
  return {
    listing: listing,
    buyer: buyer,
    commissioner: buyer,
    token: tokenAddress,
    quantity: Math.floor(Math.random() * 5) + 1,
    total: price,
    cashback: Math.floor((price * listing.cashbackPercentage) / 10000),
    commission: Math.floor((price * listing.commissionPercentage) / 10000),
    protocolFee: Math.floor((price * protocol_percentage) / 10000),
    confirmationTimeout: 0, //Math.floor(Math.random() * 30),
    timestamp: timestamp,
  };
}

module.exports = {
  generateListing,
  generateOrder,
};
