const DagoraMarket = artifacts.require("marketplace/TestDagora.sol");
const DagoraPaymaster = artifacts.require("gsn/DagoraPaymaster.sol");
const DagoraToken = artifacts.require("token/DagoraToken.sol");
const signHelper = require("./helpers/signatureHelper");

const blockchain = "localhost";

const gsn = require("@opengsn/gsn");

const RelayProvider = require("@opengsn/gsn/dist/src/relayclient/")
  .RelayProvider;

const gsnTestEnv = require("@opengsn/gsn/dist/GsnTestEnvironment").default;
const configureGSN = require("@opengsn/gsn/dist/src/relayclient/GSNConfigurator")
  .configureGSN;

const Web3 = require("web3");
const ethers = require("ethers");
const {generateListing, generateOrder} = require("./helpers/populator");
const {waitForTransaction} = require("./helpers/gsnHelper");
const {hashListing, hashOrder} = require("./helpers/signatureHelper");

const AcceptEverythingPaymaster = artifacts.require(
  "testing/AcceptEverythingPaymaster.sol"
);

contract("Dagora", async (accounts) => {
  context("Single Transactions", function () {
    let token;
    let dagora;

    before(async () => {
      token = await DagoraToken.deployed();
      dagora = await DagoraMarket.deployed();
      await token.mint(accounts[0], 100000, {from: accounts[0]});
      await token.mint(accounts[1], 100000, {from: accounts[0]});
      await dagora.grantAuthentication(token.address);
      await dagora.updateMinimumStakeToken(10);
      await dagora.updateProtocolFeePercentage(100);
    });

    it("should listing hash be equal", async () => {
      await token.approve(dagora.address, 10, {from: accounts[0]});
      await dagora.stakeTokens(10, {from: accounts[0]});

      let listing = generateListing(accounts[0]);

      var hash = hashListing(listing);

      var hashReturned = await dagora.hashListing(listing);
      assert.equal(hash, hashReturned);
    });

    it("should listing be valid with approval", async () => {
      await token.approve(dagora.address, 10, {from: accounts[0]});
      await dagora.stakeTokens(10, {from: accounts[0]});

      let listing = generateListing(accounts[0]);

      await dagora.updateListing(listing, 1);
      let valid = await dagora.requireValidListing(listing);
      assert.equal(valid.valueOf(), true);
    });

    it("should create order", async () => {
      let seller = accounts[0];
      let buyer = accounts[1];

      let sellerGasUsed = 0;
      let buyerGasUsed = 0;

      const approveSeller = await token.approve(dagora.address, -1, {
        from: seller,
      });
      sellerGasUsed += approveSeller.receipt.gasUsed;

      const approveBuyer = await token.approve(dagora.address, -1, {
        from: buyer,
      });
      buyerGasUsed += approveBuyer.receipt.gasUsed;

      const deposit = await dagora.stakeTokens(10, {from: seller});
      sellerGasUsed += deposit.receipt.gasUsed;

      let listing = generateListing(seller);

      let addProduct = await dagora.updateListing(listing, 1, {from: seller});
      sellerGasUsed += addProduct.receipt.gasUsed;

      let order = generateOrder(listing, buyer, token.address);

      let orderHash = await dagora.createTransaction(
        order,
        {from: buyer}
      );
      console.log(
        `createTransaction() gas used: ${orderHash.receipt.gasUsed}`
      );
      buyerGasUsed += orderHash.receipt.gasUsed;

      const accept = await dagora.acceptTransaction(order, {
        from: seller,
      });
      console.log(`acceptTransaction() gas used: ${accept.receipt.gasUsed}`);
      sellerGasUsed += accept.receipt.gasUsed;

      const execute = await dagora.executeTransaction(order, {
        from: seller,
      });
      console.log(`executeTransaction() gas used: ${execute.receipt.gasUsed}`);
      sellerGasUsed += execute.receipt.gasUsed;


      console.log(`Seller gas used: ${sellerGasUsed}`);
      console.log(`Buyer gas used: ${buyerGasUsed}`);
    });

    it("should create batched orders", async () => {
      let seller = accounts[0];
      let buyer = accounts[1];

      let sellerGasUsed = 0;
      let buyerGasUsed = 0;

      const approveSeller = await token.approve(dagora.address, -1, {
        from: seller,
      });
      sellerGasUsed += approveSeller.receipt.gasUsed;

      const approveBuyer = await token.approve(dagora.address, -1, {
        from: buyer,
      });
      buyerGasUsed += approveBuyer.receipt.gasUsed;

      const deposit = await dagora.stakeTokens(10, {from: seller});
      sellerGasUsed += deposit.receipt.gasUsed;

      let orders = [];
      let timestamp = 1;
      const total = 50;

      let listing = generateListing(seller);
      const updateListing = await dagora.updateListing(listing, total);
      sellerGasUsed += updateListing.receipt.gasUsed;

      for (let i = 0; i < total; i++) {
        let order = generateOrder(
          listing,
          buyer,
          token.address,
          timestamp++
        );
        orders.push(order);
      }

      let orderBatchHash = await dagora.batchCreateTransaction(
        orders,
        {from: buyer}
      );
      buyerGasUsed += orderBatchHash.receipt.gasUsed;
      console.log(
        `batchCreateTransaction() gas used per order: ${
          orderBatchHash.receipt.gasUsed / total
        }`
      );

      const accept = await dagora.batchAcceptTransaction(orders, {
        from: seller,
      });
      sellerGasUsed += accept.receipt.gasUsed;
      console.log(
        `batchAcceptTransaction() gas used per order: ${
          accept.receipt.gasUsed / total
        }`
      );

      const execute = await dagora.batchExecuteTransaction(orders, {
        from: seller,
      });
      sellerGasUsed += execute.receipt.gasUsed;
      console.log(
        `batchExecuteTransaction() gas used per order: ${
          execute.receipt.gasUsed / total
        }`
      );

      console.log(`Seller gas used: ${sellerGasUsed}`);
      console.log(`Buyer gas used: ${buyerGasUsed}`);
    });
  });

  // context("GSN", function () {
  //   let token;
  //   let dagora;

  //   let gsnInstance;
  //   let provider;
  //   let contract;

  //   before(async () => {
  //     token = await DagoraToken.deployed();
  //     dagora = await DagoraMarket.deployed();
  //     await token.mint(accounts[0], 10000, {from: accounts[0]});
  //     await token.mint(accounts[1], 10000, {from: accounts[0]});
  //     if (!dagora.contracts.call(token.address))
  //       await dagora.grantAuthentication(token.address);
  //     gsnInstance = await gsnTestEnv.startGsn(blockchain);

  //     const paymaster = await DagoraPaymaster.new();
  //     await paymaster.setRelayHub(gsnInstance.deploymentResult.relayHubAddress);
  //     await paymaster.send(1e17);
  //     await paymaster.setDagora(dagora.address);

  //     const gsnConfigParams = {
  //       gasPriceFactorPercent: 70,
  //       methodSuffix: "_v4",
  //       jsonStringifyRequest: true,
  //       chainId: "*",
  //       relayLookupWindowBlocks: 1e5,
  //       preferredRelays: [gsnInstance.relayUrl],
  //       relayHubAddress: gsnInstance.deploymentResult.relayHubAddress,
  //       stakeManagerAddress: gsnInstance.deploymentResult.stakeManagerAddress,
  //       paymasterAddress: paymaster.address,
  //       // verbose: true,
  //     };

  //     const gsnConfig = configureGSN(gsnConfigParams);

  //     provider = new ethers.providers.Web3Provider(
  //       new RelayProvider(web3.currentProvider, gsnConfig)
  //     );

  //     const acct = provider.provider.newAccount();
  //     contract = await new ethers.Contract(
  //       dagora.address,
  //       dagora.abi,
  //       provider.getSigner(acct.address, acct.privateKey)
  //     );
  //     await dagora.setTrustedForwarder(
  //       gsnInstance.deploymentResult.forwarderAddress
  //     );
  //   });

  //   it("#createTransaction", async () => {
  //     const approveSeller = await token.approve(dagora.address, -1, {
  //       from: accounts[0],
  //     });
  //     const approveBuyer = await token.approve(dagora.address, -1, {
  //       from: accounts[1],
  //     });
  //     const deposit = await dagora.stakeTokens(10, {from: accounts[0]});

  //     let listing = generateListing(accounts[0]);
  //     var listingHash = signHelper.hashListing(listing);
  //     let listingSignature = await signHelper.generateSignature(
  //       listingHash,
  //       accounts[0]
  //     );
  //     var listingHashToSign = signHelper.hashToSign(listingHash);
  //     let order = generateOrder(listing, accounts[1], token.address);

  //     var orderHash = signHelper.hashOrder(listingHashToSign, order);
  //     let orderSignature = await signHelper.generateSignature(
  //       orderHash,
  //       accounts[1]
  //     );
  //     const func = dagora.contract.methods.createTransaction(
  //       order,
  //       orderSignature,
  //       listingSignature
  //     );
  //     const transaction = await contract.createTransaction(
  //       order,
  //       orderSignature,
  //       listingSignature
  //     );
  //     const receipt = await waitForTransaction(
  //       provider,
  //       contract,
  //       transaction.hash
  //     );
  //   });

  //   // it("#createTransaction and #executeTransaction", async () => {
  //   //   const approveSeller = await token.approve(dagora.address, -1, {
  //   //     from: accounts[0],
  //   //   });
  //   //   const approveBuyer = await token.approve(dagora.address, -1, {
  //   //     from: accounts[1],
  //   //   });
  //   //   const deposit = await dagora.stakeTokens(10, {from: accounts[0]});

  //   //   let listing = generateListing(accounts[0]);
  //   //   var listingHash = signHelper.hashListing(listing);
  //   //   let listingSignature = await signHelper.generateSignature(
  //   //     listingHash,
  //   //     accounts[0]
  //   //   );
  //   //   var listingHashToSign = signHelper.hashToSign(listingHash);
  //   //   let order = generateOrder(listing, accounts[1], token.address);

  //   //   var orderHash = signHelper.hashOrder(listingHashToSign, order);
  //   //   let orderSignature = await signHelper.generateSignature(
  //   //     orderHash,
  //   //     accounts[1]
  //   //   );

  //   //   const transaction = await contract.createTransaction(
  //   //     order,
  //   //     orderSignature,
  //   //     listingSignature
  //   //   );
  //   //   await waitForTransaction(provider, contract, transaction.hash);
  //   //   transaction = await contract.executeTransaction(order);
  //   //   await waitForTransaction(provider, contract, transaction.hash);
  //   // });
  // });
});
