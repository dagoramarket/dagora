const DagoraToken = artifacts.require("token/DagoraToken.sol");

module.exports = function(_deployer) {
  _deployer.deploy(DagoraToken)
};
