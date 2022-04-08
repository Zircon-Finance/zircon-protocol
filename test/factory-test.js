const { expect } = require("chai");
const { ethers } = require('hardhat');
const assert = require("assert");

const {coreFixtures} = require("./shared/fixtures");
const TEST_ADDRESSES = [
    '0x1000000000000000000000000000000000000000',
    '0x2000000000000000000000000000000000000000'
]
let factoryPylonInstance,  token0, token1,
    pylonInstance, poolTokenInstance0, poolTokenInstance1,
    factoryInstance, deployerAddress, account2, account,
    pair;
async function addLiquidity(token0Amount, token1Amount) {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(account.address)
}



describe("Factory", function () {
    beforeEach(async () => {
        [account, account2] = await ethers.getSigners();
        deployerAddress = account.address;
        let fixtures = await coreFixtures(deployerAddress)
        factoryInstance = fixtures.factoryInstance
        token0 = fixtures.token0
        token1 = fixtures.token1
        poolTokenInstance0 = fixtures.poolTokenInstance0
        poolTokenInstance1 = fixtures.poolTokenInstance1
        pair = fixtures.pair
        pylonInstance = fixtures.pylonInstance
        factoryPylonInstance = fixtures.factoryPylonInstance
    });
    it("deploys factory", async function () {
        assert.ok(factoryInstance);
    });

    it("should fail equal pair", async function () {
        try {
            await factoryInstance.createPair(tok1Instance.address, tok1Instance.address)
            assert(false)
        }catch (e) {
            assert(e)
        }
    });

    it("should fail 0x address pair", async function () {
        try {
            await factoryInstance.createPair(ethers.constants.AddressZero, tok1Instance.address)
            assert(false)
        }catch (e) {
            assert(e)
        }

        try {
            await factoryInstance.createPair(token0.address, ethers.constants.AddressZero)
            assert(false)
        }catch (e) {
            assert(e)
        }
    });

    it("already existing pair", async function () {
        try {
            await factoryInstance.createPair(token0.address, token1.address)
            assert(false)
        }catch (e) {
            assert(e)
        }
    });

    it("creating an existing pair", async function () {
        await expect( factoryInstance.createPair(token0.address, token1.address)).to.be.revertedWith(
            'ZF: PAIR_EXISTS'
        )
    });

    it("creating a new pair", async function () {
        await factoryInstance.createPair(...TEST_ADDRESSES)
        let pairLength = await factoryInstance.allPairsLength()
        // assert.equal(3, pairLength)
    });

    // it('createPair:gas', async () => {
    //   const tx = await factoryInstance.createPair(...TEST_ADDRESSES.slice().reverse())
    //   const receipt = await tx.wait()
    //   expect(receipt.gasUsed).to.eq(5262218)
    // })

    it('should change fee', async function () {
        await factoryInstance.setFeeTo(account2.address)
        await factoryInstance.setFeeToSetter(account2.address)
        try{
            await factoryInstance.setFeeTo(account.address)
            assert(false)
        }catch (e) {
            assert(e)
        }
    });
});
