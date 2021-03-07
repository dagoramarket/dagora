const fs = require("fs");

function createCsvFile(fileName, gasCostMap, repetitions) {
  let csvContent = Object.keys(gasCostMap).join(",") + "\n";
  let rows = [];
  for (let i = 0; i < repetitions; i++) {
    rows[i] = [];
    for (let key of Object.keys(gasCostMap)) {
      rows[i].push(gasCostMap[key][i]);
    }
  }
  csvContent += rows.map((e) => e.join(",")).join("\n");
  if (!fs.existsSync("./results/")) {
    fs.mkdirSync("./results/");
  }
  fs.writeFileSync(`./results/${fileName}.csv`, csvContent, "utf8");
}

module.exports = {
  createCsvFile,
};
