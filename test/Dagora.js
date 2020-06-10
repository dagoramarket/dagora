const DagoraMarket = artifacts.require("marketplace/TestDagora.sol");
const DagoraToken = artifacts.require("token/DagoraToken.sol");
const signHelper = require("./helpers/signatureHelper");

contract("Dagora", async (accounts) => {
  before(async () => {
    const token = await DagoraToken.deployed();
    const market = await DagoraMarket.deployed();
    await token.mint(accounts[0], 10000, { from: accounts[0] });
    await token.mint(accounts[1], 10000, { from: accounts[0] });
    await market.grantAuthentication(token.address);
  });

  it("should listing be valid with signature", async () => {
    let instance = await DagoraMarket.deployed();
    let token = await DagoraToken.deployed();
    await token.approve(instance.address, 10, { from: accounts[0] });
    await instance.depositTokens(10, { from: accounts[0] });
    var block = await web3.eth.getBlock("latest");
    var address = accounts[0];

    let listing = {
      ipfsHash: web3.utils.randomHex(32),
      seller: address,
      stakeOwner: address,
      stakedAmount: 10,
      commissionPercentage: 0,
      warranty: 0,
      cashbackPercentage: 0,
      expiration: 0,
    };

    var hash = web3.utils.soliditySha3(
      listing.ipfsHash,
      listing.seller,
      listing.stakeOwner,
      listing.stakedAmount,
      listing.commissionPercentage,
      listing.warranty,
      listing.cashbackPercentage,
      listing.expiration
    );
    var hashReturned = await instance._hashListing(listing);
    assert.equal(hash, hashReturned);
    var hashToSign = web3.utils.soliditySha3(
      "\x19Ethereum Signed Message:\n32",
      hash
    );
    var hashToSignReturned = await instance._hashListingToSign(listing);
    assert.equal(hashToSign, hashToSignReturned);
    let signature = await signHelper.generateSignature(hash, address);

    // await instance.approveListing(listing);
    let valid = await instance._requireValidListing(listing, signature);
    assert.equal(valid.valueOf(), true);
  });

  it("should listing be valid with approval", async () => {
    let instance = await DagoraMarket.deployed();
    let token = await DagoraToken.deployed();
    await token.approve(instance.address, 10, { from: accounts[0] });
    await instance.depositTokens(10, { from: accounts[0] });
    var block = await web3.eth.getBlock("latest");
    var address = accounts[0];

    let listing = {
      ipfsHash: web3.utils.randomHex(32),
      seller: address,
      stakeOwner: address,
      stakedAmount: 10,
      commissionPercentage: 0,
      warranty: 0,
      cashbackPercentage: 0,
      expiration: 0,
    };

    let signature = {
      v: 0,
      r: web3.utils.randomHex(32),
      s: web3.utils.randomHex(32),
    };

    await instance.approveListing(listing);
    let valid = await instance._requireValidListing(listing, signature);
    assert.equal(valid.valueOf(), true);
  });

  it("should create order", async () => {
    let sellerGasUsed = 0;
    let buyerGasUsed = 0;
    const instance = await DagoraMarket.deployed();
    const token = await DagoraToken.deployed();
    const approveSeller = await token.approve(instance.address, -1, {
      from: accounts[0],
    });
    sellerGasUsed += approveSeller.receipt.gasUsed;
    const approveBuyer = await token.approve(instance.address, -1, {
      from: accounts[1],
    });
    buyerGasUsed += approveBuyer.receipt.gasUsed;
    const deposit = await instance.depositTokens(10, { from: accounts[0] });
    sellerGasUsed += deposit.receipt.gasUsed;
    var address = accounts[0];

    let listing = {
      ipfsHash: web3.utils.randomHex(32),
      seller: address,
      stakeOwner: address,
      stakedAmount: 10,
      commissionPercentage: 0,
      warranty: 0,
      cashbackPercentage: 0,
      expiration: 0,
    };

    var listingHash = web3.utils.soliditySha3(
      listing.ipfsHash,
      listing.seller,
      listing.stakeOwner,
      listing.stakedAmount,
      listing.commissionPercentage,
      listing.warranty,
      listing.cashbackPercentage,
      listing.expiration
    );
    let listingSignature = await signHelper.generateSignature(listingHash, address);
    var hashToSign = web3.utils.soliditySha3(
      "\x19Ethereum Signed Message:\n32",
      listingHash
    );
    let order = {
      listing: listing,
      buyer: accounts[1],
      fundsHolder: accounts[1],
      commissioner: accounts[1],
      token: token.address,
      total: 500,
      cashback: 0,
      commission: 0,
      protocolFee: 1,
      stakeHolderFee: 0,
      expiration: 0,
      confirmationTimeout: 0,
      timestamp: 0
    };

    var orderHash = web3.utils.soliditySha3(
      hashToSign,
      order.buyer,
      order.fundsHolder,
      order.commissioner,
      order.token,
      order.total,
      order.cashback,
      order.commission,
      order.protocolFee,
      order.stakeHolderFee,
      order.expiration,
      order.confirmationTimeout,
      order.timestamp
    );
    let orderSignature = await signHelper.generateSignature(
      orderHash,
      accounts[1]
    );
    let orderHashToSign = await instance.createTransaction(
      order,
      orderSignature,
      listingSignature,
      { from: accounts[0] }
    );
    console.log(`createTransaction() gas used: ${orderHashToSign.receipt.gasUsed}`);
    sellerGasUsed += orderHashToSign.receipt.gasUsed;
    const confirm = await instance.executeTransaction(order, {
      from: accounts[0],
    });
    console.log(`executeTransaction() gas used: ${confirm.receipt.gasUsed}`);
    sellerGasUsed += confirm.receipt.gasUsed;
    console.log(`Seller gas used: ${sellerGasUsed}`);
    console.log(`Buyer gas used: ${buyerGasUsed}`);
  });

  it("should create batched orders", async () => {
    let sellerGasUsed = 0;
    let buyerGasUsed = 0;
    const instance = await DagoraMarket.deployed();
    const token = await DagoraToken.deployed();
    const approveSeller = await token.approve(instance.address, -1, {
      from: accounts[0],
    });
    sellerGasUsed += approveSeller.receipt.gasUsed;
    const approveBuyer = await token.approve(instance.address, -1, {
      from: accounts[1],
    });
    buyerGasUsed += approveBuyer.receipt.gasUsed;
    const deposit = await instance.depositTokens(10, { from: accounts[0] });
    sellerGasUsed += deposit.receipt.gasUsed;
    var address = accounts[0];

    let listing = {
      ipfsHash: web3.utils.randomHex(32),
      seller: accounts[2],
      stakeOwner: address,
      stakedAmount: 10,
      commissionPercentage: 0,
      warranty: 0,
      cashbackPercentage: 0,
      expiration: 0,
    };

    var listingHash = web3.utils.soliditySha3(
      listing.ipfsHash,
      listing.seller,
      listing.stakeOwner,
      listing.stakedAmount,
      listing.commissionPercentage,
      listing.warranty,
      listing.cashbackPercentage,
      listing.expiration
    );
    let listingSignature = await signHelper.generateSignature(listingHash, address);
    var hashToSign = web3.utils.soliditySha3(
      "\x19Ethereum Signed Message:\n32",
      listingHash
    );
    let orders = [];
    let ordersSignatures = [];
    let listingsSignatures = [];
    let timestamp = 1;
    const total = 50;
    for (let i = 0; i < total; i++) {
      let order = {
        listing: listing,
        buyer: accounts[1],
        fundsHolder: accounts[1],
        commissioner: accounts[3],
        token: token.address,
        total: 10,
        cashback: 1,
        commission: 1,
        protocolFee: 1,
        stakeHolderFee: 1,
        expiration: 0,
        confirmationTimeout: 0,
        timestamp: timestamp++
      };
      var orderHash = web3.utils.soliditySha3(
        hashToSign,
        order.buyer,
        order.fundsHolder,
        order.commissioner,
        order.token,
        order.total,
        order.cashback,
        order.commission,
        order.protocolFee,
        order.stakeHolderFee,
        order.expiration,
        order.confirmationTimeout,
        order.timestamp
      );
      let orderSignature = await signHelper.generateSignature(
        orderHash,
        accounts[1]
      );
      orders.push(order);
      ordersSignatures.push(orderSignature);
      listingsSignatures.push(listingSignature);
    }

    
    let orderBatchHashToSign = await instance.batchCreateTransaction(
      orders,
      ordersSignatures,
      listingsSignatures,
      { from: accounts[0] }
    );
    // console.log(`createTransaction() gas used: ${orderBatchHashToSign.receipt.gasUsed}`);
    console.log(`batchCreateTransaction() gas used per order: ${orderBatchHashToSign.receipt.gasUsed / total}`);
    sellerGasUsed += orderBatchHashToSign.receipt.gasUsed;
    const execute = await instance.batchExecuteTransaction(orders, {
      from: accounts[0],
    });
    console.log(`batchExecuteTransaction() gas used per order: ${execute.receipt.gasUsed / total}`);
    // sellerGasUsed += confirm.receipt.gasUsed;
    console.log(`Seller gas used: ${sellerGasUsed}`);
    console.log(`Buyer gas used: ${buyerGasUsed}`);
  });
});
