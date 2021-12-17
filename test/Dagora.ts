import type {
  TestDagora as DagoraMarket,
  DagoraToken,
  CentralizedArbitrator,
} from "../typechain";
import { ethers } from "hardhat";

import { generateListing, generateOrder } from "./helpers/populator";
// const { waitForTransaction } = require("./helpers/gsnHelper");
// import { advanceTime } from "./helpers/testHelper";
import { hashListing } from "./helpers/signatureHelper";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { expect } from "chai";

describe("Dagora", async () => {
  context("Single Transactions", () => {
    let token: DagoraToken;
    let dagora: DagoraMarket;
    let arbitrator: CentralizedArbitrator;
    let protocol_percentage: number;
    let owner: SignerWithAddress,
      buyer: SignerWithAddress,
      seller: SignerWithAddress;
    before(async () => {
      const DagoraMarket = await ethers.getContractFactory("TestDagora");
      const DagoraToken = await ethers.getContractFactory("DagoraToken");
      const CentralizedArbitrator = await ethers.getContractFactory(
        "CentralizedArbitrator"
      );
      token = (await DagoraToken.deploy()) as DagoraToken;
      await token.deployed();
      arbitrator = (await CentralizedArbitrator.deploy(
        30
      )) as CentralizedArbitrator;
      await arbitrator.deployed();
      dagora = (await DagoraMarket.deploy(
        arbitrator.address,
        arbitrator.address,
        token.address,
        arbitrator.address,
        ethers.utils.randomBytes(32),
        ethers.utils.randomBytes(32),
        "http://ipfs.dagora.market/"
      )) as DagoraMarket;
      await dagora.deployed();
      [owner, buyer, seller] = await ethers.getSigners();

      await token.mint(owner.address, 100000);
      await token.mint(buyer.address, 100000);
      await token.mint(seller.address, 100000);
      await dagora.grantAuthentication(token.address);
      await dagora.updateMinimumStakeToken(10);
      protocol_percentage = 100;
      await dagora.updateProtocolFeePercentage(protocol_percentage);
    });

    it("should listing hash be equal", async () => {
      await token.approve(dagora.address, 10);
      await dagora.stakeTokens(10);

      let listing = generateListing(seller.address);

      var hash = hashListing(listing);

      var hashReturned = await dagora.hashListing(listing);
      expect(hashReturned).to.be.equal(hash);
    });

    it("should listing be valid with approval", async () => {
      await token.connect(seller).approve(dagora.address, 10);
      await dagora.connect(seller).stakeTokens(10);

      let listing = generateListing(seller.address);

      await dagora.connect(seller).updateListing(listing, 1);
      let valid = await dagora.requireValidListing(listing);
      expect(valid.valueOf()).to.be.true;
    });

    it("should create order", async () => {
      const approveSellerTx = await token
        .connect(seller)
        .approve(dagora.address, ethers.constants.MaxUint256);
      await approveSellerTx.wait();
      const approveBuyerTx = await token
        .connect(buyer)
        .approve(dagora.address, ethers.constants.MaxUint256);
      await approveBuyerTx.wait();
      const depositTx = await dagora.connect(seller).stakeTokens(10);
      await depositTx.wait();
      let listing = generateListing(seller.address);

      const addProductTx = await dagora
        .connect(seller)
        .updateListing(listing, 5);
      await addProductTx.wait();
      let order = generateOrder(
        listing,
        buyer.address,
        token.address,
        protocol_percentage
      );

      const orderHashTx = await dagora.connect(buyer).createTransaction(order);
      const orderReceipt = await orderHashTx.wait();
      console.log(`createTransaction() gas used: ${orderReceipt.gasUsed}`);

      const accept = await dagora.connect(seller).acceptTransaction(order);
      const acceptReceipt = await accept.wait();
      console.log(`acceptTransaction() gas used: ${acceptReceipt.gasUsed}`);

      const execute = await dagora.connect(seller).executeTransaction(order);
      const executeReceipt = await execute.wait();
      console.log(`executeTransaction() gas used: ${executeReceipt.gasUsed}`);
    });

    // it("should create batched orders", async () => {
    //   let seller = accounts[0];
    //   let buyer = accounts[1];

    //   let sellerGasUsed = 0;
    //   let buyerGasUsed = 0;

    //   const approveSeller = await token.approve(dagora.address, -1, {
    //     from: seller,
    //   });
    //   sellerGasUsed += approveSeller.receipt.gasUsed;

    //   const approveBuyer = await token.approve(dagora.address, -1, {
    //     from: buyer,
    //   });
    //   buyerGasUsed += approveBuyer.receipt.gasUsed;

    //   const deposit = await dagora.stakeTokens(10, { from: seller });
    //   sellerGasUsed += deposit.receipt.gasUsed;

    //   let orders = [];
    //   let timestamp = 1;
    //   const total = 50;

    //   let listing = generateListing(seller);
    //   const updateListing = await dagora.updateListing(listing, total * 5);
    //   sellerGasUsed += updateListing.receipt.gasUsed;

    //   for (let i = 0; i < total; i++) {
    //     let order = generateOrder(
    //       listing,
    //       buyer,
    //       token.address,
    //       protocol_percentage,
    //       timestamp++
    //     );
    //     orders.push(order);
    //   }

    //   let orderBatchHash = await dagora.batchCreateTransaction(orders, {
    //     from: buyer,
    //   });
    //   buyerGasUsed += orderBatchHash.receipt.gasUsed;
    //   console.log(
    //     `batchCreateTransaction() gas used per order: ${
    //       orderBatchHash.receipt.gasUsed / total
    //     }`
    //   );

    //   const accept = await dagora.batchAcceptTransaction(orders, {
    //     from: seller,
    //   });
    //   sellerGasUsed += accept.receipt.gasUsed;
    //   console.log(
    //     `batchAcceptTransaction() gas used per order: ${
    //       accept.receipt.gasUsed / total
    //     }`
    //   );

    //   const execute = await dagora.batchExecuteTransaction(orders, {
    //     from: seller,
    //   });
    //   sellerGasUsed += execute.receipt.gasUsed;
    //   console.log(
    //     `batchExecuteTransaction() gas used per order: ${
    //       execute.receipt.gasUsed / total
    //     }`
    //   );

    //   console.log(`Seller gas used: ${sellerGasUsed}`);
    //   console.log(`Buyer gas used: ${buyerGasUsed}`);
    // });
  });

  // context("Gas cost evaluation", function () {
  //   let token;
  //   let dagora;
  //   let protocol_percentage;
  //   let dispute_timeout;
  //   let GAS_EVALUATION = {
  //     stakeTokens: [],
  //     unstakeTokens: [],
  //     updateListing: [],
  //     cancelListing: [],
  //     createTransaction: [],
  //     cancelTransaction: [],
  //     acceptTransaction: [],
  //     executeTransaction: [],
  //     confirmReceipt: [],
  //     claimWarranty: [],
  //     updateRefund: [],
  //     disputeTransaction: [],
  //     report: [],
  //     disputeTimeout: [],
  //     claimWarranty: [],
  //     appeal: [],
  //     batchCreateTransaction: [],
  //     batchAcceptTransaction: [],
  //     batchCancelTransaction: [],
  //     batchExecuteTransaction: [],
  //   };
  //   let REPETITIONS = 15;

  //   before(async () => {
  //     token = await DagoraToken.deployed();
  //     dagora = await DagoraMarket.deployed();
  //     arbitrator = await CentralizedArbitrator.deployed();
  //     await token.mint(accounts[0], 100000);
  //     await token.mint(accounts[1], 100000);
  //     if (!dagora.contracts.call(token.address))
  //       await dagora.grantAuthentication(token.address);
  //     await dagora.updateMinimumStakeToken(10);
  //     protocol_percentage = 100; // 1%
  //     await dagora.updateProtocolFeePercentage(protocol_percentage);
  //     dispute_timeout = 7; // 7 days
  //     await dagora.updateDisputeTimeout(dispute_timeout);
  //   });

  //   it("contract deploy", async () => {
  //     GAS_EVALUATION = {
  //       contract_deploy: [],
  //     };

  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let someInstance = await DagoraMarket.new(
  //         arbitrator.address,
  //         arbitrator.address,
  //         token.address,
  //         arbitrator.address,
  //         web3.utils.toHex("a"),
  //         web3.utils.toHex("a"),
  //         "http://ipfs.infura.io/ipfs/"
  //       );
  //       let receipt = await web3.eth.getTransactionReceipt(
  //         someInstance.transactionHash
  //       );
  //       GAS_EVALUATION.contract_deploy.push(receipt.gasUsed);
  //     }
  //     createCsvFile("contract_deploy", GAS_EVALUATION, REPETITIONS);
  //   });

  //   it("successful flow with expiration", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       executeTransaction: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, false, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       advanceTime(order.confirmationTimeout * 24 * 60 * 60); // seconds

  //       let executeTransaction = await dagora.executeTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "executeTransaction", executeTransaction);
  //     }
  //     createCsvFile("success_expiration", GAS_EVALUATION, REPETITIONS);
  //   });

  //   it("successful flow without warranty and buyer confirmation", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       confirmReceipt: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, false, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);
  //     }
  //     createCsvFile(
  //       "success_no_warranty_buyer_confirm",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("successful flow with warranty and buyer confirmation", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       confirmReceipt: [],
  //       executeTransaction: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);

  //       advanceTime(order.listing.warranty * 24 * 60 * 60); // seconds

  //       let executeTransaction = await dagora.executeTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "executeTransaction", executeTransaction);
  //     }
  //     createCsvFile(
  //       "success_warranty_buyer_confirm",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("successful flow with refund", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       updateRefund: [],
  //       confirmReceipt: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let updateRefund = await dagora.updateRefund(
  //         order,
  //         order.cashback +
  //           1 +
  //           Math.floor(
  //             Math.random() *
  //               (order.total -
  //                 order.protocolFee -
  //                 order.commission -
  //                 order.cashback -
  //                 1)
  //           ),
  //         {
  //           from: seller,
  //         }
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateRefund", updateRefund);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);
  //     }
  //     createCsvFile("success_refund", GAS_EVALUATION, REPETITIONS);
  //   });

  //   it("unsuccessful flow with claim warranty and expiration", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       confirmReceipt: [],
  //       claimWarranty: [],
  //       executeTransaction: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);

  //       let claimWarranty = await dagora.claimWarranty(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "claimWarranty", claimWarranty);

  //       advanceTime(order.confirmationTimeout * 24 * 60 * 60); // seconds

  //       let executeTransaction = await dagora.executeTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "executeTransaction", executeTransaction);
  //     }
  //     createCsvFile(
  //       "unsuccess_claim_warranty_expire",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("unsuccessful flow with claim warranty and confirmation", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       buyerConfirmReceipt: [],
  //       claimWarranty: [],
  //       sellerConfirmReceipt: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let buyerConfirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(
  //         GAS_EVALUATION,
  //         "buyerConfirmReceipt",
  //         buyerConfirmReceipt
  //       );

  //       let claimWarranty = await dagora.claimWarranty(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "claimWarranty", claimWarranty);

  //       advanceTime(order.confirmationTimeout * 24 * 60 * 60); // seconds

  //       let sellerConfirmReceipt = await dagora.confirmReceipt(order, {
  //         from: seller,
  //       });
  //       updateGasCost(
  //         GAS_EVALUATION,
  //         "sellerConfirmReceipt",
  //         sellerConfirmReceipt
  //       );
  //     }
  //     createCsvFile(
  //       "unsuccess_claim_warranty_confirm",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("unsuccessful flow with buyer dispute and seller timeout", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       disputeTransaction: [],
  //       disputeTimeout: [],
  //     };

  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let cost = (await dagora.arbitrationCost(2)).toNumber();
  //       let disputeTransaction = await dagora.disputeTransaction(order, {
  //         from: buyer,
  //         value: cost,
  //       });

  //       updateGasCost(GAS_EVALUATION, "disputeTransaction", disputeTransaction);

  //       advanceTime(dispute_timeout * 24 * 60 * 60); // seconds

  //       let disputeHash = hashOrder(order);
  //       let disputeTimeout = await dagora.disputeTimeout(disputeHash, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "disputeTimeout", disputeTimeout);
  //     }
  //     createCsvFile(
  //       "unsuccess_dispute_seller_timeout",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("unsuccessful flow with buyer dispute and seller accept", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       disputeTransaction: [],
  //       payArbitrationFee: [],
  //       giveRuling: [],
  //     };

  //     let judge = accounts[0];
  //     let seller = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let cost = (await dagora.arbitrationCost(2)).toNumber();
  //       let disputeTransaction = await dagora.disputeTransaction(order, {
  //         from: buyer,
  //         value: cost,
  //       });

  //       updateGasCost(GAS_EVALUATION, "disputeTransaction", disputeTransaction);

  //       let disputeHash = hashOrder(order);
  //       let payArbitrationFee = await dagora.payArbitrationFee(disputeHash, {
  //         from: seller,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "payArbitrationFee", payArbitrationFee);
  //       let dispute = await dagora.disputes.call(disputeHash);
  //       let giveRuling = await arbitrator.giveRuling(
  //         dispute.disputeId,
  //         Math.floor(Math.random() * 3),
  //         {
  //           from: judge,
  //         }
  //       );
  //       updateGasCost(GAS_EVALUATION, "giveRuling", giveRuling);
  //     }
  //     createCsvFile(
  //       "unsuccess_dispute_seller_accepts",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("unsuccessful flow with warranty dispute and buyer timeout", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       confirmReceipt: [],
  //       claimWarranty: [],
  //       disputeTransaction: [],
  //       disputeTimeout: [],
  //     };

  //     let seller = accounts[0];
  //     let judge = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);

  //       let claimWarranty = await dagora.claimWarranty(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "claimWarranty", claimWarranty);

  //       let cost = (await dagora.arbitrationCost(2)).toNumber();
  //       let disputeTransaction = await dagora.disputeTransaction(order, {
  //         from: seller,
  //         value: cost,
  //       });

  //       updateGasCost(GAS_EVALUATION, "disputeTransaction", disputeTransaction);

  //       advanceTime(dispute_timeout * 24 * 60 * 60); // seconds

  //       let disputeHash = hashOrder(order);
  //       let disputeTimeout = await dagora.disputeTimeout(disputeHash, {
  //         from: judge,
  //       });
  //       updateGasCost(GAS_EVALUATION, "disputeTimeout", disputeTimeout);
  //     }
  //     createCsvFile(
  //       "unsuccess_warranty_dispute_timeout",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("unsuccessful flow with warranty dispute and buyer accept", async () => {
  //     GAS_EVALUATION = {
  //       stakeTokens: [],
  //       updateListing: [],
  //       createTransaction: [],
  //       acceptTransaction: [],
  //       confirmReceipt: [],
  //       claimWarranty: [],
  //       disputeTransaction: [],
  //       payArbitrationFee: [],
  //       giveRuling: [],
  //     };

  //     let seller = accounts[0];
  //     let judge = accounts[0];
  //     let buyer = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: buyer });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let stakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "stakeTokens", stakeTokens);
  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let order = generateOrder(
  //         listing,
  //         buyer,
  //         token.address,
  //         protocol_percentage,
  //         new Date().getTime(),
  //         true
  //       );
  //       let createTransaction = await dagora.createTransaction(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "createTransaction", createTransaction);

  //       let acceptTransaction = await dagora.acceptTransaction(order, {
  //         from: seller,
  //       });
  //       updateGasCost(GAS_EVALUATION, "acceptTransaction", acceptTransaction);

  //       let confirmReceipt = await dagora.confirmReceipt(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "confirmReceipt", confirmReceipt);

  //       let claimWarranty = await dagora.claimWarranty(order, {
  //         from: buyer,
  //       });
  //       updateGasCost(GAS_EVALUATION, "claimWarranty", claimWarranty);

  //       let cost = (await dagora.arbitrationCost(2)).toNumber();
  //       let disputeTransaction = await dagora.disputeTransaction(order, {
  //         from: seller,
  //         value: cost,
  //       });

  //       updateGasCost(GAS_EVALUATION, "disputeTransaction", disputeTransaction);

  //       let disputeHash = hashOrder(order);
  //       let payArbitrationFee = await dagora.payArbitrationFee(disputeHash, {
  //         from: buyer,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "payArbitrationFee", payArbitrationFee);

  //       let disputeId = (await dagora.disputes.call(disputeHash)).disputeId;
  //       let giveRuling = await arbitrator.giveRuling(
  //         disputeId,
  //         Math.floor(Math.random() * 3),
  //         {
  //           from: judge,
  //         }
  //       );
  //       updateGasCost(GAS_EVALUATION, "giveRuling", giveRuling);
  //     }
  //     createCsvFile(
  //       "unsuccess_warranty_dispute_accept",
  //       GAS_EVALUATION,
  //       REPETITIONS
  //     );
  //   });

  //   it("report and seller expire", async () => {
  //     GAS_EVALUATION = {
  //       sellerStakeTokens: [],
  //       reporterStakeTokens: [],
  //       updateListing: [],
  //       report: [],
  //       disputeTimeout: [],
  //     };

  //     let seller = accounts[0];
  //     let reporter = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: reporter });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let sellerStakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "sellerStakeTokens", sellerStakeTokens);

  //       let reporterStakeTokens = await dagora.stakeTokens(10, {
  //         from: reporter,
  //       });

  //       updateGasCost(
  //         GAS_EVALUATION,
  //         "reporterStakeTokens",
  //         reporterStakeTokens
  //       );

  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let cost = (await dagora.arbitrationCost(1)).toNumber();
  //       let report = await dagora.report(listing, {
  //         from: reporter,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "report", report);

  //       advanceTime(dispute_timeout * 24 * 60 * 60); // seconds

  //       let disputeHash = hashListing(listing);
  //       let disputeTimeout = await dagora.disputeTimeout(disputeHash, {
  //         from: reporter,
  //       });
  //       updateGasCost(GAS_EVALUATION, "disputeTimeout", disputeTimeout);
  //     }
  //     createCsvFile("report_seller_expire", GAS_EVALUATION, REPETITIONS);
  //   });

  //   it("report and seller accept, reporter wins", async () => {
  //     GAS_EVALUATION = {
  //       sellerStakeTokens: [],
  //       reporterStakeTokens: [],
  //       updateListing: [],
  //       report: [],
  //       payArbitrationFee: [],
  //       giveRuling: [],
  //     };

  //     let judge = accounts[0];
  //     let seller = accounts[0];
  //     let reporter = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: reporter });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let sellerStakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "sellerStakeTokens", sellerStakeTokens);

  //       let reporterStakeTokens = await dagora.stakeTokens(10, {
  //         from: reporter,
  //       });

  //       updateGasCost(
  //         GAS_EVALUATION,
  //         "reporterStakeTokens",
  //         reporterStakeTokens
  //       );

  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let cost = (await dagora.arbitrationCost(1)).toNumber();
  //       let report = await dagora.report(listing, {
  //         from: reporter,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "report", report);

  //       let disputeHash = hashListing(listing);

  //       let payArbitrationFee = await dagora.payArbitrationFee(disputeHash, {
  //         from: seller,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "payArbitrationFee", payArbitrationFee);

  //       let dispute = await dagora.disputes.call(disputeHash);
  //       let giveRuling = await arbitrator.giveRuling(dispute.disputeId, 1, {
  //         from: judge,
  //       });
  //       updateGasCost(GAS_EVALUATION, "giveRuling", giveRuling);
  //     }
  //     createCsvFile("report_reporter_wins", GAS_EVALUATION, REPETITIONS);
  //   });

  //   it("report and seller accept, seller wins", async () => {
  //     GAS_EVALUATION = {
  //       sellerStakeTokens: [],
  //       reporterStakeTokens: [],
  //       updateListing: [],
  //       report: [],
  //       payArbitrationFee: [],
  //       giveRuling: [],
  //     };

  //     let judge = accounts[0];
  //     let seller = accounts[0];
  //     let reporter = accounts[1];

  //     await token.approve(dagora.address, -1, { from: seller });
  //     await token.approve(dagora.address, -1, { from: reporter });
  //     for (let i = 0; i < REPETITIONS; i++) {
  //       let sellerStakeTokens = await dagora.stakeTokens(10, { from: seller });

  //       updateGasCost(GAS_EVALUATION, "sellerStakeTokens", sellerStakeTokens);

  //       let reporterStakeTokens = await dagora.stakeTokens(10, {
  //         from: reporter,
  //       });

  //       updateGasCost(
  //         GAS_EVALUATION,
  //         "reporterStakeTokens",
  //         reporterStakeTokens
  //       );

  //       let listing = generateListing(seller, true, false);

  //       let updateListing = await dagora.updateListing(
  //         listing,
  //         Math.floor(Math.random() * 100) + 5
  //       );
  //       updateGasCost(GAS_EVALUATION, "updateListing", updateListing);

  //       let cost = (await dagora.arbitrationCost(1)).toNumber();
  //       let report = await dagora.report(listing, {
  //         from: reporter,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "report", report);

  //       let disputeHash = hashListing(listing);

  //       let payArbitrationFee = await dagora.payArbitrationFee(disputeHash, {
  //         from: seller,
  //         value: cost,
  //       });
  //       updateGasCost(GAS_EVALUATION, "payArbitrationFee", payArbitrationFee);

  //       let dispute = await dagora.disputes.call(disputeHash);
  //       let giveRuling = await arbitrator.giveRuling(dispute.disputeId, 2, {
  //         from: judge,
  //       });
  //       updateGasCost(GAS_EVALUATION, "giveRuling", giveRuling);
  //       advanceTime(dispute_timeout * 24 * 60 * 60); // seconds
  //     }
  //     createCsvFile("report_seller_wins", GAS_EVALUATION, REPETITIONS);
  //   });

  //   // it("listing update", async () => {
  //   //   await token.approve(dagora.address, 10);
  //   //   await dagora.stakeTokens(10);
  //   //   for (let i = 0; i < REPETITIONS; i++) {
  //   //     let listing = generateListing(accounts[0]);
  //   //     let updateListing = await dagora.updateListing(listing, 1);
  //   //     let valid = await dagora.requireValidListing(listing);
  //   //     assert.equal(valid.valueOf(), true);
  //   //     console.log(
  //   //       `updateListing() gas used: ${updateListing.receipt.gasUsed}`
  //   //     );
  //   //     updateGasCost(GAS_EVALUATION, "updateListing", updateListing);
  //   //   }
  //   // });

  //   // it("create transaction", async () => {
  //   //   let seller = accounts[0];
  //   //   let buyer = accounts[1];

  //   //   let gasUsed = 0;
  //   //   await token.approve(dagora.address, 10, { from: seller });
  //   //   await dagora.stakeTokens(10, { from: seller });

  //   //   await token.approve(dagora.address, -1, {
  //   //     from: buyer,
  //   //   });

  //   //   let listing = generateListing(seller);
  //   //   await dagora.updateListing(listing, REPETITIONS * 5);
  //   //   let valid = await dagora.requireValidListing(listing);
  //   //   assert.equal(valid.valueOf(), true);

  //   //   let timestamp = 1;
  //   //   for (let i = 0; i < REPETITIONS; i++) {
  //   //     let order = generateOrder(
  //   //       listing,
  //   //       buyer,
  //   //       token.address,
  //   //       protocol_percentage,
  //   //       timestamp++
  //   //     );
  //   //     let orderHash = await dagora.createTransaction(order, { from: buyer });
  //   //     console.log(
  //   //       `createTransaction() gas used: ${orderHash.receipt.gasUsed}`
  //   //     );
  //   //     gasUsed += orderHash.receipt.gasUsed;
  //   //   }
  //   //   console.log(
  //   //     `createTransaction() AVERAGE GAS USED: ${gasUsed / REPETITIONS}`
  //   //   );
  //   // });
  // });
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
