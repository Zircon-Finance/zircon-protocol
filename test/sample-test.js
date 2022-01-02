const { expect } = require("chai");
const { ethers } = require('hardhat');
const assert = require("assert");

let factory, tok1Instance, tok1, tok2, tok2Instance,
    pylonInstance, poolTokenInstance1, poolTokenInstance2,
    factoryInstance, deployerAddress, account2;

before(async () => {
  [account, account2] = await ethers.getSigners();
  deployerAddress = account.address;

  factory = await ethers.getContractFactory('ZirconFactory');
  factoryInstance = await factory.deploy(deployerAddress);

  //Deploy Tokens
  tok1 = await ethers.getContractFactory('Token');
  tok1Instance = await tok1.deploy('Token1', 'TOK1');
  tok2 = await ethers.getContractFactory('Token');
  tok2Instance = await tok2.deploy('Token2', 'TOK2');

  await factoryInstance.createPair(tok1Instance.address, tok2Instance.address);
  const lpAddress = await factoryInstance.getPair(
      tok1Instance.address,
      tok2Instance.address
  );
  const pylonAddress = await factoryInstance.getPylon(lpAddress);
  let zPylon = await ethers.getContractFactory('ZirconPylon')
  let poolToken1 = await ethers.getContractFactory('ZirconPoolToken')
  let poolToken2 = await ethers.getContractFactory('ZirconPoolToken')

  pylonInstance = zPylon.attach(pylonAddress);
  let poolAddress1 = await pylonInstance.floatPoolToken();
  let poolAddress2 = await pylonInstance.anchorPoolToken();

  poolTokenInstance1 = poolToken1.attach(poolAddress1)
  poolTokenInstance2 = poolToken2.attach(poolAddress2)

});

describe("Factory", function () {
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
      await factoryInstance.createPair(tok1Instance.address, ethers.constants.AddressZero)
      assert(false)
    }catch (e) {
      assert(e)
    }
  });

  it("already existing pair", async function () {
    try {
      await factoryInstance.createPair(tok1Instance.address, tok2Instance.address)
      assert(false)
    }catch (e) {
      assert(e)
    }
  });

  it("creating a new inverted pair", async function () {
    await factoryInstance.createPair(tok2Instance.address, tok1Instance.address)
    let pairLength = await factoryInstance.allPairsLength()
    assert.equal(2, pairLength)
  });

  it("creating a new  pair", async function () {
    await factoryInstance.createPair(account.address, account2.address)
    let pairLength = await factoryInstance.allPairsLength()
    assert.equal(3, pairLength)
  });
  
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
