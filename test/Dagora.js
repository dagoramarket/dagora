const DagoraMarket = artifacts.require("marketplace/TestDagora.sol");
const DagoraToken = artifacts.require("token/DagoraToken.sol");
const signHelper = require("./helpers/signatureHelper");

contract("Dagora", async accounts => {
    before(async () => {
        let token = await DagoraToken.deployed();
        await token.mint(accounts[0], 1000, { from: accounts[0] });
      });

    it("should listing be valid with signature", async () => {
        let instance = await DagoraMarket.deployed();
        let token = await DagoraToken.deployed();
        await token.approve(instance.address, 10, { from: accounts[0] })
        await instance.depositTokens(10, { from: accounts[0] });
        var block = await web3.eth.getBlock('latest');
        var address = accounts[0];

        let listing = {
            ipfsHash: web3.utils.randomHex(32),
            seller: address,
            stakeOwner: address,
            stakedAmount: 10,
            commissionPercentage: 0,
            creationTimestamp: block.timestamp,
            warrantyTimeout: 0,
            expiration: 0
        };

        var hash = web3.utils.soliditySha3(listing.ipfsHash,
                                            listing.seller,
                                            listing.stakeOwner,
                                            listing.stakedAmount,
                                            listing.commissionPercentage,
                                            listing.creationTimestamp,
                                            listing.warrantyTimeout,
                                            listing.expiration);
        var hashReturned = await instance._hashListing(listing);
        assert.equal(hash, hashReturned);
        var hashToSign = web3.utils.soliditySha3("\x19Ethereum Signed Message:\n32", hash);
        var hashToSignReturned = await instance._hashListingToSign(listing);
        assert.equal(hashToSign, hashToSignReturned);
        let signature = await signHelper.generateSignature(hash, address);

        // await instance.approveListing(listing);
        let valid = await instance._requireValidListing(listing, signature);
        assert.equal(valid.valueOf(), true);
    });

    it("should listing be valid with approval", async () => {
        let instance = await DagoraMarket.deployed();
        let token = await DagoraToken.deployed();
        await token.approve(instance.address, 10, { from: accounts[0] })
        await instance.depositTokens(10, { from: accounts[0] });
        var block = await web3.eth.getBlock('latest');
        var address = accounts[0];

        let listing = {
            ipfsHash: web3.utils.randomHex(32),
            seller: address,
            stakeOwner: address,
            stakedAmount: 10,
            commissionPercentage: 0,
            creationTimestamp: block.timestamp,
            warrantyTimeout: 0,
            expiration: 0
        };

        let signature = {
            v: 0,
            r: web3.utils.randomHex(32),
            s: web3.utils.randomHex(32)
        };

        await instance.approveListing(listing);
        let valid = await instance._requireValidListing(listing, signature);
        assert.equal(valid.valueOf(), true);
    });
});