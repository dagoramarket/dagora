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
const {waitForTransaction} = require("./helpers/gsnHelper");
const {hashListing, hashOrder} = require("./helpers/signatureHelper");

contract("Paymaster", async (accounts) => {
  context("GSN", function () {
    let token;
    let dagora;

    // let gsnInstance;
    // let provider;
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
      await paymaster.send(1e17);
      await paymaster.setDagora(dagora.address);

      // const gsnConfigParams = {
      //   gasPriceFactorPercent: 70,
      //   methodSuffix: "_v4",
      //   jsonStringifyRequest: true,
      //   chainId: "*",
      //   relayLookupWindowBlocks: 1e5,
      //   preferredRelays: [gsnInstance.relayUrl],
      //   relayHubAddress: gsnInstance.deploymentResult.relayHubAddress,
      //   stakeManagerAddress: gsnInstance.deploymentResult.stakeManagerAddress,
      //   paymasterAddress: paymaster.address,
      //   // verbose: true,
      // };

      // const gsnConfig = configureGSN(gsnConfigParams);

      // provider = new ethers.providers.Web3Provider(
      //   new RelayProvider(web3.currentProvider, gsnConfig)
      // );

      // const acct = provider.provider.newAccount();
      // contract = await new ethers.Contract(
      //   dagora.address,
      //   dagora.abi,
      //   provider.getSigner(acct.address, acct.privateKey)
      // );
      // await dagora.setTrustedForwarder(
      //   gsnInstance.deploymentResult.forwarderAddress
      // );
    });

    it("#createTransaction", async () => {
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
