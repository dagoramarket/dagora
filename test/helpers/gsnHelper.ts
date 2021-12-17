export async function waitForTransaction(
  provider: any,
  contract: any,
  txHash: any
) {
  const receipt = await provider.waitForTransaction(txHash);

  const result = receipt.logs
    .map((entry: any) => contract.interface.parseLog(entry))
    .filter((entry: any) => entry != null)[0];

  return result.values["0"];
}
