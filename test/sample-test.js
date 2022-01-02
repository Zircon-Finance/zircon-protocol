const { expect } = require("chai");
const { ethers } = require('hardhat');
const assert = require("assert");

const TEST_ADDRESSES = [
  '0x1000000000000000000000000000000000000000',
  '0x2000000000000000000000000000000000000000'
]

let factory, tok1Instance, tok1, tok2, tok2Instance,
    pylonInstance, poolTokenInstance1, poolTokenInstance2,
    factoryInstance, deployerAddress, account2, account,
    lpAddress;

const MINIMUM_LIQUIDITY = ethers.BigNumber.from(10).pow(3)

function expandTo18Decimals(n) {return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18))}

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
  lpAddress = await factoryInstance.getPair(
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

  it("creating a new pair", async function () {
    await factoryInstance.createPair(...TEST_ADDRESSES)
    let pairLength = await factoryInstance.allPairsLength()
    assert.equal(3, pairLength)
  });

  it('createPair:gas', async () => {
    const tx = await factoryInstance.createPair(...TEST_ADDRESSES.slice().reverse())
    const receipt = await tx.wait()
    expect(receipt.gasUsed).to.eq(5236609)
  })

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

describe("Pair", () => {
  it('mint', async () => {
    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await tok1Instance.transfer(lpAddress, token0Amount)
    await tok2Instance.transfer(lpAddress, token1Amount)

    let pairFactory = await ethers.getContractFactory("ZirconPair");
    let pair = await pairFactory.attach(lpAddress);


    const expectedLiquidity = expandTo18Decimals(2)
    await expect(pair.mint(account.address))
        .to.emit(pair, 'Transfer')
        .withArgs(ethers.constants.AddressZero, ethers.constants.AddressZero, MINIMUM_LIQUIDITY)
        .to.emit(pair, 'Transfer')
        .withArgs(ethers.constants.AddressZero, account.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount, token1Amount)
        .to.emit(pair, 'Mint')
        .withArgs(account.address, token0Amount, token1Amount)

    expect(await pair.totalSupply()).to.eq(expectedLiquidity)
    expect(await pair.balanceOf(account.address)).to.eq(expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(token0Amount)
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(token1Amount)
    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount)
    expect(reserves[1]).to.eq(token1Amount)
  })
})
