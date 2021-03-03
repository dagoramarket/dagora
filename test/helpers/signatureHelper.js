async function generateSignature(hash, address) {
  let sig = await web3.eth.sign(hash, address);
  if (sig.slice(0, 2) === "0x") sig = sig.substr(2);
  var r = "0x" + sig.substr(0, 64);
  var s = "0x" + sig.substr(64, 64);
  var v = web3.utils.toDecimal(sig.substr(128, 2)) + 27;
  var ret = {};
  ret.r = r;
  ret.s = s;
  ret.v = v;
  return ret;
}

function hashListing(_listing) {
  return web3.utils.soliditySha3(
    _listing.ipfsHash,
    _listing.seller,
    _listing.commissionPercentage,
    _listing.warranty,
    _listing.cashbackPercentage,
    _listing.expiration
  );
}

function hashOrder(listingHash, _order) {
  return web3.utils.soliditySha3(
    listingHash,
    _order.buyer,
    _order.commissioner,
    _order.token,
    _order.quantity,
    _order.total,
    _order.cashback,
    _order.commission,
    _order.protocolFee,
    _order.confirmationTimeout,
    _order.timestamp
  );
}

function hashToSign(_hash) {
  return web3.utils.soliditySha3("\x19Ethereum Signed Message:\n32", _hash);
}

module.exports = {
  generateSignature,
  hashListing,
  hashOrder,
  hashToSign,
};
