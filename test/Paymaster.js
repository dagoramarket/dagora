const DagoraMarket = artifacts.require("marketplace/TestDagora.sol");
const DagoraPaymaster = artifacts.require("gsn/DagoraPaymaster.sol");
const DagoraToken = artifacts.require("token/DagoraToken.sol");
const AcceptEverythingPaymaster = artifacts.require(
  "testing/AcceptEverythingPaymaster.sol"
);

const AcceptForwarder = artifacts.require("testing/AcceptForwarder.sol");
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

contract("Paymaster", async (accounts) => {
  context("methods", function () {
    let token;
    let dagora;

    let paymaster;

    before(async () => {
      token = await DagoraToken.deployed();
      dagora = await DagoraMarket.deployed();
      await token.mint(accounts[0], 10000, {from: accounts[0]});
      await token.mint(accounts[1], 10000, {from: accounts[0]});
      if (!dagora.contracts.call(token.address))
        await dagora.grantAuthentication(token.address);
      gsnInstance = await gsnTestEnv.startGsn(blockchain);

      paymaster = await DagoraPaymaster.new();
      await paymaster.setRelayHub(gsnInstance.deploymentResult.relayHubAddress);
      await paymaster.setDagora(dagora.address);
    });

    it("#acceptRelayedCall", async () => {
      const approveSeller = await token.approve(dagora.address, -1, {
        from: accounts[0],
      });
      const approveBuyer = await token.approve(dagora.address, -1, {
        from: accounts[1],
      });
      const deposit = await dagora.depositTokens(10, {from: accounts[0]});

      let listing = generateListing(accounts[0]);
      var listingHash = signHelper.hashListing(listing);
      let listingSignature = await signHelper.generateSignature(
        listingHash,
        accounts[0]
      );
      var listingHashToSign = signHelper.hashToSign(listingHash);
      let order = generateOrder(listing, accounts[1], token.address);

      var orderHash = signHelper.hashOrder(listingHashToSign, order);
      let orderSignature = await signHelper.generateSignature(
        orderHash,
        accounts[1]
      );
      const func = dagora.contract.methods.createTransaction(
        order,
        orderSignature,
        listingSignature
      );

      const forwarder = await AcceptForwarder.new();

      const relayRequest = {
        target: accounts[0],
        encodedFunction: func.encodeABI(),
        gasData: {
          gasLimit: 0,
          gasPrice: 0,
          pctRelayFee: 0,
          baseRelayFee: 0,
        },
        relayData: {
          senderAddress: accounts[0],
          senderNonce: 0,
          relayWorker: accounts[0],
          paymaster: paymaster.address,
          forwarder: forwarder.address,
        },
      };
      await paymaster.acceptRelayedCall(
        relayRequest,
        web3.utils.randomHex(32),
        web3.utils.randomHex(32),
        0,
        {
          from: accounts[0],
        }
      );
    });
  });
});
