async function waitForTransaction(provider, contract, txHash) {
  const receipt = await provider.waitForTransaction(txHash);

  const result = receipt.logs
    .map((entry) => contract.interface.parseLog(entry))
    .filter((entry) => entry != null)[0];

  return result.values["0"];
}

module.exports = {
  waitForTransaction,
};
