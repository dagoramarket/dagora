
async function generateSignature(hash, address) {
    let sig = await web3.eth.sign(hash, address);
    if (sig.slice(0, 2) === '0x') 
        sig = sig.substr(2);
    var r = '0x' + sig.substr(0, 64);
    var s = '0x' + sig.substr(64, 64);
    var v =  web3.utils.toDecimal(sig.substr(128, 2)) + 27
    var ret = {};
    ret.r = r;
    ret.s = s;
    ret.v = v;
    return ret;
}

module.exports = {
    generateSignature
}