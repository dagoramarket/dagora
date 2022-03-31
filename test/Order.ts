import type {
  DagoraToken,
  StakeManager,
  ListingManager,
  DisputeManager,
  OrderManager,
  TestDisputeManager,
} from "../typechain";
import { ethers } from "hardhat";

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, should } from "chai";
import {
  generateListing,
  generateOrder,
  Listing,
  Order,
} from "./helpers/populator";
import { hashListing, hashOrder, toHex } from "./helpers/signatureHelper";
import { advanceTimeAndBlock } from "./helpers/testHelper";
import { BigNumber } from "ethers";

const MINIMUM_STAKE = 1000; // 1000 DGR
const PERCENTAGE_BURN = 1000; // 10%
const PERCENTAGE_FEE = 100; // 1%

should();

describe("Order", async () => {
  let token: DagoraToken;
  let orderManager: OrderManager;
  let stakeManager: StakeManager;
  let listingManager: ListingManager;
  let disputeManager: TestDisputeManager;
  let owner: SignerWithAddress,
    buyer: SignerWithAddress,
    seller: SignerWithAddress,
    commissioner: SignerWithAddress;

  let arbCost: BigNumber;

  before(async () => {
    [owner, buyer, seller, commissioner] = await ethers.getSigners();

    const StakeManager = await ethers.getContractFactory("StakeManager");
    const TestDisputeManager = await ethers.getContractFactory(
      "TestDisputeManager"
    );
    const DagoraToken = await ethers.getContractFactory("DagoraToken");
    const PercentageLib = await ethers.getContractFactory("PercentageLib");
    const percentageLib = await PercentageLib.deploy();
    const DagoraLib = await ethers.getContractFactory("DagoraLib");
    const dagoraLib = await DagoraLib.deploy();
    const ListingManager = await ethers.getContractFactory("ListingManager", {
      libraries: {
        PercentageLib: percentageLib.address,
        DagoraLib: dagoraLib.address,
      },
    });
    const OrderManager = await ethers.getContractFactory("OrderManager", {
      libraries: {
        PercentageLib: percentageLib.address,
        DagoraLib: dagoraLib.address,
      },
    });

    token = (await DagoraToken.deploy()) as DagoraToken;
    await token.deployed();

    stakeManager = (await StakeManager.deploy(token.address)) as StakeManager;
    stakeManager.deployed();

    disputeManager = (await TestDisputeManager.deploy()) as TestDisputeManager;

    arbCost = await disputeManager.arbitrationCost();
    listingManager = (await ListingManager.deploy(
      stakeManager.address,
      disputeManager.address,
      MINIMUM_STAKE,
      PERCENTAGE_BURN
    )) as ListingManager;

    await (await stakeManager.setOperator(listingManager.address)).wait();

    orderManager = (await OrderManager.deploy(
      listingManager.address,
      disputeManager.address,
      owner.address,
      PERCENTAGE_FEE
    )) as OrderManager;
    await orderManager.deployed();

    await token.mint(owner.address, 100000);
    await token.mint(buyer.address, 100000);
    await token.mint(seller.address, 100000);

    await (
      await token
        .connect(seller)
        .approve(stakeManager.address, ethers.constants.MaxUint256)
    ).wait();
    await (
      await token
        .connect(buyer)
        .approve(orderManager.address, ethers.constants.MaxUint256)
    ).wait();

    const stakeTx = await stakeManager
      .connect(seller)
      .stakeTokens(MINIMUM_STAKE * 2);
    await stakeTx.wait();
  });

  context("#requireValidOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        0,
        true,
        commissioner.address
      );
      hash = hashOrder(order);
    });
    it("buyer and seller the same", async () => {
      order = generateOrder(
        listing,
        seller.address,
        token.address,
        PERCENTAGE_FEE
      );

      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("commissioner equal buyer or seller", async () => {
      order.commissioner = seller.address;

      let validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;

      order.commissioner = buyer.address;

      validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("commisioner equals zero", async () => {
      order.commissioner = ethers.constants.AddressZero;
      order.commission = 1;

      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("commision not enough", async () => {
      order.listing.commissionPercentage = 100;
      order.commission = 0;

      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("cashback not enough", async () => {
      order.listing.cashbackPercentage = 100;
      order.cashback = 0;

      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("protocol fee not enough", async () => {
      order.protocolFee = order.protocolFee - 1;

      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
    it("not enough money", async () => {
      order.protocolFee = order.total;
      order.cashback = order.cashback + 1;
      order.commission = order.commission + 1;
      const validOrder = orderManager.requireValidOrder(order);
      await expect(validOrder).to.be.reverted;
    });
  });

  context("#createOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
    });
    it("should create order", async () => {
      const balanceBefore = await token.balanceOf(buyer.address);

      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const balanceAfter = await token.balanceOf(buyer.address);
      const listingHash = hashListing(listing);

      const transaction = await orderManager.transactions(hash);
      expect(transaction.status).to.be.equal(1); // WaitingSeller

      expect(balanceBefore.sub(balanceAfter)).to.be.equal(order.total);
      expect(createOrderTx)
        .to.emit(orderManager, "TransactionCreated")
        .withArgs(
          hash,
          listingHash,
          order.buyer,
          order.commissioner,
          order.token,
          order.total,
          order.commission,
          order.cashback,
          order.confirmationTimeout
        );
    });
    it("invalid phase", async () => {
      await (await orderManager.connect(buyer).createOrder(order)).wait();

      const createOrderTx = orderManager.connect(buyer).createOrder(order);
      await expect(createOrderTx).to.be.revertedWith("IP");
    });
    it("transfer failed", async () => {
      const DagoraToken = await ethers.getContractFactory("DagoraToken");
      const anotherToken = (await DagoraToken.deploy()) as DagoraToken;
      await anotherToken.deployed();
      order = generateOrder(
        listing,
        buyer.address,
        anotherToken.address,
        PERCENTAGE_FEE
      );
      const createOrderTx = orderManager.connect(buyer).createOrder(order);
      await expect(createOrderTx).to.be.reverted;
    });
  });

  context("#cancelOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();
    });
    it("should cancel order by buyer", async () => {
      const balanceBefore = await token.balanceOf(buyer.address);
      const cancelOrderTx = await orderManager
        .connect(buyer)
        .cancelOrder(order);
      await cancelOrderTx.wait();

      const transactions = await orderManager.transactions(hash);
      const balanceAfter = await token.balanceOf(buyer.address);

      transactions.status.should.be.equal(0); // Canceled
      expect(transactions.lastStatusUpdate).to.be.equal(0);
      expect(balanceAfter.sub(balanceBefore)).to.be.equal(order.total);
      expect(cancelOrderTx)
        .to.emit(orderManager, "TransactionCancelled")
        .withArgs(hash);
    });
    it("should cancel order by seller", async () => {
      const balanceBefore = await token.balanceOf(buyer.address);
      const cancelOrderTx = await orderManager
        .connect(seller)
        .cancelOrder(order);
      await cancelOrderTx.wait();

      const transactions = await orderManager.transactions(hash);
      const balanceAfter = await token.balanceOf(buyer.address);

      expect(transactions.status).to.be.equal(0); // Canceled
      expect(transactions.lastStatusUpdate).to.be.equal(0);
      expect(balanceAfter.sub(balanceBefore)).to.be.equal(order.total);
      expect(cancelOrderTx)
        .to.emit(orderManager, "TransactionCancelled")
        .withArgs(hash);
    });
    it("shouldn't cancel order not buyer or seller", async () => {
      const cancelOrderTx = orderManager.connect(owner).cancelOrder(order);
      await expect(cancelOrderTx).to.be.revertedWith("MBBS");
    });
    it("shouldn't cancel order that doesn't exist", async () => {
      order = order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      const cancelOrderTx = orderManager.connect(buyer).cancelOrder(order);
      await expect(cancelOrderTx).to.be.revertedWith("IP");
    });
  });
  context("#acceptOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();
    });
    it("should accept order", async () => {
      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(2); // WaitingConfirmation
      expect(acceptOrderTx)
        .to.emit(orderManager, "TransactionAccepted")
        .withArgs(hash);
    });
    it("shouldn't accept order if not seller", async () => {
      const acceptOrderTx = orderManager.acceptOrder(order);
      await expect(acceptOrderTx).to.be.revertedWith("MBS");
    });
    it("shouldn't accept order that doesn't exist", async () => {
      order = order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      const acceptOrderTx = orderManager.connect(seller).acceptOrder(order);
      await expect(acceptOrderTx).to.be.revertedWith("IP");
    });
  });
  context("#confirmReceipt()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address, true);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
    });
    it("should confirm receipt and finalize transaction", async () => {
      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(3); // Warranty
      expect(confirmReceiptTx)
        .to.emit(orderManager, "TransactionConfirmed")
        .withArgs(hash);
    });
    it("only buyer can confirm receipt", async () => {
      const confirmReceiptTx = orderManager.confirmReceipt(order);
      await expect(confirmReceiptTx).to.be.revertedWith("MBB");
    });
    it("only waiting for confirmation orders", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      const confirmReceiptTx = orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await expect(confirmReceiptTx).to.be.revertedWith("IP");
    });
    it("listing doesn't have warranty", async () => {
      listing = generateListing(seller.address, false);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const confirmReceiptTx = orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await expect(confirmReceiptTx).to.be.revertedWith("NEW");
    });
    it("refunded order not eligible", async () => {
      const updateRefundTx = await orderManager
        .connect(seller)
        .updateRefund(
          order,
          order.total - order.protocolFee - order.commission
        );
      await updateRefundTx.wait();
      const confirmReceiptTx = orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await expect(confirmReceiptTx).to.be.revertedWith("NEW");
    });
  });
  context("#executeOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        0,
        true,
        commissioner.address
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
    });
    it("should confirm receipt and finalize transaction", async () => {
      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(6); // Finalized
      expect(executeOrderTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(
        order.cashback
      );
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(order.commission);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(order.protocolFee);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total - order.commission - order.cashback - order.protocolFee
      );
    });
    it("should execute by anyone after timeout", async () => {
      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      advanceTimeAndBlock(order.confirmationTimeout * 24 * 60 * 60); // x days

      const executeOrderTx = await orderManager.executeOrder(order);
      await executeOrderTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);
      expect(executeOrderTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(0);
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(order.commission);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(order.protocolFee);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total - order.commission - order.protocolFee
      );
    });
    it("shouldn't finalize by anyone no timeout", async () => {
      const executeOrderTx = orderManager.executeOrder(order);
      await expect(executeOrderTx).to.be.revertedWith("TNPY");
    });
    it("warranty ineligible because of refund", async () => {
      listing = generateListing(seller.address, true);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        0,
        true,
        commissioner.address
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const refund = order.total - order.protocolFee - order.commission;
      const refundTx = await orderManager
        .connect(seller)
        .updateRefund(order, refund);
      await refundTx.wait();

      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      expect(executeOrderTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(refund);
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(order.commission);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(order.protocolFee);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total - order.commission - order.protocolFee - refund
      );
    });
    it("no protocol fee", async () => {
      const oldProtocolFee = PERCENTAGE_FEE;
      const setProtocolFee = await orderManager.updateProtocolFeePercentage(0);
      await setProtocolFee.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        0,
        0,
        true,
        commissioner.address
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      expect(executeOrderTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(
        order.cashback
      );
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(order.commission);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(order.protocolFee);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total - order.commission - order.protocolFee - order.cashback
      );

      const setProtocolFee2 = await orderManager.updateProtocolFeePercentage(
        oldProtocolFee
      );
      await setProtocolFee2.wait();
    });
    it("no cashback or refund", async () => {
      listing = generateListing(seller.address);
      listing.cashbackPercentage = 0;
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        0,
        true,
        commissioner.address
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      expect(executeOrderTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(
        order.cashback
      );
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(order.commission);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(order.protocolFee);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total - order.commission - order.protocolFee - order.cashback
      );
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        0,
        true,
        commissioner.address
      );
      let executeOrderTx = orderManager.executeOrder(order);
      await expect(executeOrderTx).to.be.revertedWith("IP");
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      executeOrderTx = orderManager.executeOrder(order);
      await expect(executeOrderTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const executeOrderTx2 = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx2.wait();

      executeOrderTx = orderManager.executeOrder(order);
      await expect(executeOrderTx).to.be.revertedWith("IP");
    });
  });
  context("#updateRefund()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
    });
    it("should update refund", async () => {
      const refund = Math.floor(order.total / 2);
      const updateRefundTx = await orderManager
        .connect(seller)
        .updateRefund(order, refund);
      await updateRefundTx.wait();

      const transactions = await orderManager.transactions(hash);
      expect(transactions.refund).to.be.equal(refund);

      expect(updateRefundTx)
        .to.emit(orderManager, "TransactionRefunded")
        .withArgs(hash, refund);
    });
    it("confirmation timed out", async () => {
      advanceTimeAndBlock(order.confirmationTimeout * 24 * 60 * 60); // x days
      const refund = Math.floor(order.total / 2);
      const updateRefundTx = orderManager
        .connect(seller)
        .updateRefund(order, refund);
      await expect(updateRefundTx).to.be.revertedWith("CTO");
    });
    it("refund less than cashback", async () => {
      const refund = order.cashback - 1;
      const updateRefundTx = orderManager
        .connect(seller)
        .updateRefund(order, refund);
      await expect(updateRefundTx).to.be.revertedWith("RGC");
    });
    it("refund greater than available", async () => {
      const refund = order.total - order.protocolFee - order.commission;
      const updateRefundTx = orderManager
        .connect(seller)
        .updateRefund(order, refund + 1);
      await expect(updateRefundTx).to.be.revertedWith("RGA");
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      const refund = Math.floor(order.total / 2);
      let updateRefundTx = orderManager
        .connect(seller)
        .updateRefund(order, refund);
      await expect(updateRefundTx).to.be.revertedWith("IP");
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();
      updateRefundTx = orderManager.connect(seller).updateRefund(order, refund);
      await expect(updateRefundTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      updateRefundTx = orderManager.connect(seller).updateRefund(order, refund);
      await expect(updateRefundTx).to.be.revertedWith("IP");
    });
  });
  context("#claimWarranty()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address, true);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();
    });
    it("should claim warranty", async () => {
      const claimWarrantyTx = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx.wait();

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(4); // WaitingWarranty
      expect(claimWarrantyTx)
        .to.emit(orderManager, "WarrantyClaimed")
        .withArgs(hash);
    });
    it("warranty timed out", async () => {
      advanceTimeAndBlock(order.listing.warranty * 24 * 60 * 60); // x days
      const claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("WTO");
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);

      let claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("IP");

      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("IP");

      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();

      const claimWarrantyTx2 = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx2.wait();

      claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("IP");

      const confirmWarrantyReceiptTx = await orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await confirmWarrantyReceiptTx.wait();

      claimWarrantyTx = orderManager.connect(buyer).claimWarranty(order);
      await expect(claimWarrantyTx).to.be.revertedWith("IP");
    });
  });
  context("#confirmWarrantyReceipt()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address, true);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();
      const claimWarrantyTx = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx.wait();
    });
    it("should claim warranty", async () => {
      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const confirmWarrantyReceiptTx = await orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await confirmWarrantyReceiptTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(6); // Finalized
      expect(confirmWarrantyReceiptTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(
        order.total
      );
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(0);
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(0);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(0);
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);

      let confirmWarrantyReceiptTx = orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await expect(confirmWarrantyReceiptTx).to.be.revertedWith("IP");

      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      confirmWarrantyReceiptTx = orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await expect(confirmWarrantyReceiptTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      confirmWarrantyReceiptTx = orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await expect(confirmWarrantyReceiptTx).to.be.revertedWith("IP");

      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();

      confirmWarrantyReceiptTx = orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await expect(confirmWarrantyReceiptTx).to.be.revertedWith("IP");

      const claimWarrantyTx = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx.wait();

      const confirmWarrantyReceiptTx2 = await orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await confirmWarrantyReceiptTx2.wait();

      confirmWarrantyReceiptTx = orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await expect(confirmWarrantyReceiptTx).to.be.revertedWith("IP");
    });
  });

  context("#disputeOrder()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
    });

    it("should dispute order", async () => {
      const disputeOrderTx = await orderManager
        .connect(buyer)
        .disputeOrder(order, {
          value: arbCost,
        });
      await disputeOrderTx.wait();

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(5); // InDispute
      expect(disputeOrderTx)
        .to.emit(disputeManager, "HasToPayFee")
        .withArgs(hash, 1);
    });
    it("dispute timed out", async () => {
      advanceTimeAndBlock(order.confirmationTimeout * 24 * 60 * 60); // x days
      const disputeOrderTx = orderManager.connect(buyer).disputeOrder(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("CTO");
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );

      let disputeOrderTx = orderManager.connect(buyer).disputeOrder(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");

      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      disputeOrderTx = orderManager.connect(buyer).disputeOrder(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      const executeOrderTx = await orderManager
        .connect(buyer)
        .executeOrder(order);
      await executeOrderTx.wait();

      disputeOrderTx = orderManager.connect(buyer).disputeOrder(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");
    });
  });
  context("#disputeWarranty()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address, true);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();
      const claimWarrantyTx = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx.wait();
    });

    it("should dispute warranty", async () => {
      const disputeWarrantyTx = await orderManager
        .connect(seller)
        .disputeWarranty(order, {
          value: arbCost,
        });
      await disputeWarrantyTx.wait();

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(5); // InDispute
      expect(disputeWarrantyTx)
        .to.emit(disputeManager, "HasToPayFee")
        .withArgs(hash, 1);
    });
    it("dispute warranty timed out", async () => {
      advanceTimeAndBlock(order.confirmationTimeout * 24 * 60 * 60); // x days
      const disputeOrderTx = orderManager
        .connect(seller)
        .disputeWarranty(order, {
          value: arbCost,
        });
      await expect(disputeOrderTx).to.be.revertedWith("CTO");
    });
    it("invalid phase", async () => {
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE,
        1
      );
      let disputeOrderTx = orderManager.connect(seller).disputeWarranty(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      disputeOrderTx = orderManager.connect(seller).disputeWarranty(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();

      disputeOrderTx = orderManager.connect(seller).disputeWarranty(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");

      const confirmReceiptTx = await orderManager
        .connect(buyer)
        .confirmReceipt(order);
      await confirmReceiptTx.wait();

      disputeOrderTx = orderManager.connect(seller).disputeWarranty(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");

      const claimWarrantyTx = await orderManager
        .connect(buyer)
        .claimWarranty(order);
      await claimWarrantyTx.wait();

      const confirmWarrantyReceiptTx = await orderManager
        .connect(seller)
        .confirmWarrantyReceipt(order);
      await confirmWarrantyReceiptTx.wait();

      disputeOrderTx = orderManager.connect(seller).disputeWarranty(order, {
        value: arbCost,
      });
      await expect(disputeOrderTx).to.be.revertedWith("IP");
    });
  });
  context("#rullingCallback()", () => {
    let listing: Listing;
    let hash: string;
    let order: Order;
    beforeEach(async () => {
      listing = generateListing(seller.address);
      const createListingTx = await listingManager
        .connect(seller)
        .createListing(listing, 10);
      await createListingTx.wait();
      order = generateOrder(
        listing,
        buyer.address,
        token.address,
        PERCENTAGE_FEE
      );
      hash = hashOrder(order);
      const createOrderTx = await orderManager
        .connect(buyer)
        .createOrder(order);
      await createOrderTx.wait();

      const acceptOrderTx = await orderManager
        .connect(seller)
        .acceptOrder(order);
      await acceptOrderTx.wait();
      const disputeOrderTx = await orderManager
        .connect(buyer)
        .disputeOrder(order, {
          value: arbCost,
        });
      await disputeOrderTx.wait();
    });

    it("rule in favor of buyer", async () => {
      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const ruleTx = await disputeManager.rule(hash, 1);
      await ruleTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(6); // Finalized
      expect(ruleTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(
        order.total
      );
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(0);
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(0);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(0);
    });
    it("rule in favor of seller", async () => {
      const buyerBalanceBefore = await token.balanceOf(order.buyer);
      const sellerBalanceBefore = await token.balanceOf(order.listing.seller);
      const commissionerBalanceBefore = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceBefore = await token.balanceOf(owner.address);

      const ruleTx = await disputeManager.rule(hash, 2);
      await ruleTx.wait();

      const buyerBalanceAfter = await token.balanceOf(order.buyer);
      const sellerBalanceAfter = await token.balanceOf(order.listing.seller);
      const commissionerBalanceAfter = await token.balanceOf(
        order.commissioner
      );
      const feeRecipientBalanceAfter = await token.balanceOf(owner.address);

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(6); // Finalized
      expect(ruleTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      expect(buyerBalanceAfter.sub(buyerBalanceBefore)).to.be.equal(0);
      expect(sellerBalanceAfter.sub(sellerBalanceBefore)).to.be.equal(
        order.total
      );
      expect(
        commissionerBalanceAfter.sub(commissionerBalanceBefore)
      ).to.be.equal(0);
      expect(
        feeRecipientBalanceAfter.sub(feeRecipientBalanceBefore)
      ).to.be.equal(0);
    });
    it("rule in favor of neither", async () => {
      const dispute = await disputeManager.getDispute(hash);

      const defendantBalanceBefore = await token.balanceOf(dispute.defendant);
      const prosecutionBalanceBefore = await token.balanceOf(
        dispute.prosecution
      );
      const ruleTx = await disputeManager.rule(hash, 0);
      await ruleTx.wait();

      const defendantBalanceAfter = await token.balanceOf(dispute.defendant);
      const prosecutionBalanceAfter = await token.balanceOf(
        dispute.prosecution
      );

      const transactions = await orderManager.transactions(hash);

      expect(transactions.status).to.be.equal(6); // Finalized
      expect(ruleTx)
        .to.emit(orderManager, "TransactionFinalized")
        .withArgs(hash);
      const half = Math.floor(order.total / 2);
      expect(defendantBalanceAfter.sub(defendantBalanceBefore)).to.be.equal(
        order.total - half
      );
      expect(prosecutionBalanceAfter.sub(prosecutionBalanceBefore)).to.be.equal(
        half
      );
    });
  });
});
