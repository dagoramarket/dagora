const CentralizedArbitrator = artifacts.require("testing/CentralizedArbitrator.sol");

module.exports = function(_deployer) {
  _deployer.deploy(CentralizedArbitrator, 30);
};
