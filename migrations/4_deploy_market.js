const DagoraToken = artifacts.require("token/DagoraToken.sol");
const CentralizedArbitrator = artifacts.require(
  "testing/CentralizedArbitrator.sol"
);
const DagoraMarket = artifacts.require("marketplace/TestDagora.sol");

module.exports = function (_deployer) {
  var token, arbitrator;
  _deployer
    .then(function () {
      // Create a new version of A
      return DagoraToken.deployed();
    })
    .then(function (instance) {
      token = instance.address;
      // Get the deployed instance of B
      return CentralizedArbitrator.deployed();
    })
    .then(function (instance) {
      arbitrator = instance.address;
      // Get the deployed instance of B
      return _deployer.deploy(
        DagoraMarket,
        arbitrator,
        token,
        arbitrator,
        1,
        1,
        30,
        30,
        web3.utils.toHex("a"),
        web3.utils.toHex("a"),
        "http://ipfs.infura.io/ipfs/",
        arbitrator
      );
    });
};
