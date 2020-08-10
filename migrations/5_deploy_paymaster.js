const DagoraPaymaster = artifacts.require("gsn/DagoraPaymaster.sol");

module.exports = function (_deployer) {
  _deployer.deploy(DagoraPaymaster);
};
