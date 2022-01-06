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
    lpAddress, pair;

const MINIMUM_LIQUIDITY = ethers.BigNumber.from(10).pow(3)
const overrides = {
  gasLimit: 9999999
}
function expandTo18Decimals(n) {return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18))}

beforeEach(async () => {
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

  let pairFactory = await ethers.getContractFactory("ZirconPair");
  pair = await pairFactory.attach(lpAddress);

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
    // assert.equal(2, pairLength)
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

describe("Pair", () => {
  // Same as Uniswap v2 - CORE
  it('mint', async () => {
    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await tok1Instance.transfer(lpAddress, token0Amount)
    await tok2Instance.transfer(lpAddress, token1Amount)

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

  async function addLiquidity(token0Amount, token1Amount) {
    await tok1Instance.transfer(pair.address, token0Amount)
    await tok2Instance.transfer(pair.address, token1Amount)
    await pair.mint(account.address)
  }

  const swapTestCases = [
    [1, 5, 10, '1662497915624478906'],
    [1, 10, 5, '453305446940074565'],

    [2, 5, 10, '2851015155847869602'],
    [2, 10, 5, '831248957812239453'],

    [1, 10, 10, '906610893880149131'],
    [1, 100, 100, '987158034397061298'],
    [1, 1000, 1000, '996006981039903216']
  ].map(a => a.map(n => (typeof n === 'string' ? ethers.BigNumber.from(n) : expandTo18Decimals(n))))
  swapTestCases.forEach((swapTestCase, i) => {
    it(`getInputPrice:${i}`, async () => {
      const [swapAmount, token0Amount, token1Amount, expectedOutputAmount] = swapTestCase
      await addLiquidity(token0Amount, token1Amount)

      await tok1Instance.transfer(pair.address, swapAmount)
      await expect(pair.swap(0, expectedOutputAmount.add(1), account.address, '0x')).to.be.revertedWith(
          'UniswapV2: K'
      )
      await pair.swap(0, expectedOutputAmount, account.address, '0x')
    })
  })
  it('swap:token0', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('1662497915624478906')
    await tok1Instance.transfer(pair.address, swapAmount)
    await expect(pair.swap(0, expectedOutputAmount, account.address, '0x', overrides))
        .to.emit(tok2Instance, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'Swap')
        .withArgs(account.address, swapAmount, 0, 0, expectedOutputAmount, account.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount))
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount))
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount))
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await tok1Instance.totalSupply()
    const totalSupplyToken1 = await tok2Instance.totalSupply()
    expect(await tok1Instance.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await tok2Instance.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
  })

  it('swapNoFee:token0', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('2000000000000000000')
    await tok1Instance.transfer(pair.address, swapAmount)
    await expect(pair.swapNoFee(0, expectedOutputAmount, account.address, '0x', overrides))
        .to.emit(tok2Instance, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'Swap')
        .withArgs(account.address, swapAmount, 0, 0, expectedOutputAmount, account.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount))
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount))
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount))
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await tok1Instance.totalSupply()
    const totalSupplyToken1 = await tok2Instance.totalSupply()
    expect(await tok1Instance.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await tok2Instance.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
  })

  it('swap:token1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('453305446940074565')
    await tok2Instance.transfer(pair.address, swapAmount)
    await expect(pair.swap(expectedOutputAmount, 0, account.address, '0x', overrides))
        .to.emit(tok1Instance, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.sub(expectedOutputAmount), token1Amount.add(swapAmount))
        .to.emit(pair, 'Swap')
        .withArgs(account.address, 0, swapAmount, expectedOutputAmount, 0, account.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.sub(expectedOutputAmount))
    expect(reserves[1]).to.eq(token1Amount.add(swapAmount))
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(token0Amount.sub(expectedOutputAmount))
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(token1Amount.add(swapAmount))
    const totalSupplyToken0 = await tok1Instance.totalSupply()
    const totalSupplyToken1 = await tok2Instance.totalSupply()
    expect(await tok1Instance.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(token0Amount).add(expectedOutputAmount))
    expect(await tok2Instance.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(token1Amount).sub(swapAmount))
  })

  it('burn', async () => {
    const token0Amount = expandTo18Decimals(3)
    const token1Amount = expandTo18Decimals(3)
    await addLiquidity(token0Amount, token1Amount)

    const expectedLiquidity = expandTo18Decimals(3)
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await expect(pair.burn(account.address, overrides))
        .to.emit(pair, 'Transfer')
        .withArgs(pair.address, ethers.constants.AddressZero, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
        .to.emit(tok1Instance, 'Transfer')
        .withArgs(pair.address, account.address, token0Amount.sub(1000))
        .to.emit(tok1Instance, 'Transfer')
        .withArgs(pair.address, account.address, token1Amount.sub(1000))
        .to.emit(pair, 'Sync')
        .withArgs(1000, 1000)
        .to.emit(pair, 'Burn')
        .withArgs(account.address, token0Amount.sub(1000), token1Amount.sub(1000), account.address)

    expect(await pair.balanceOf(account.address)).to.eq(0)
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(1000)
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(1000)
    const totalSupplyToken0 = await tok1Instance.totalSupply()
    const totalSupplyToken1 = await tok2Instance.totalSupply()
    expect(await tok1Instance.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(1000))
    expect(await tok2Instance.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(1000))
  })

  it('feeTo:off', async () => {
    const token0Amount = expandTo18Decimals(1000)
    const token1Amount = expandTo18Decimals(1000)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('996006981039903216')
    await tok2Instance.transfer(pair.address, swapAmount)
    await pair.swap(expectedOutputAmount, 0, account.address, '0x', overrides)

    const expectedLiquidity = expandTo18Decimals(1000)
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await pair.burn(account.address, overrides)
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
  })


  it('feeTo:on', async () => {
    await factoryInstance.setFeeTo(account2.address)

    const token0Amount = expandTo18Decimals(1000)
    const token1Amount = expandTo18Decimals(1000)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('996006981039903216')
    await tok2Instance.transfer(pair.address, swapAmount)
    await pair.swap(expectedOutputAmount, 0, account.address, '0x', overrides)

    const expectedLiquidity = expandTo18Decimals(1000)
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await pair.burn(account.address, overrides)
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY.add('249750499251388'))
    expect(await pair.balanceOf(account2.address)).to.eq('249750499251388')

    // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
    // ...because the initial liquidity amounts were equal
    expect(await tok1Instance.balanceOf(pair.address)).to.eq(ethers.BigNumber.from(1000).add('249501683697445'))
    expect(await tok2Instance.balanceOf(pair.address)).to.eq(ethers.BigNumber.from(1000).add('250000187312969'))
  })


  it('should add users', async function () {
    await expect(pair.removeApprovedUser(account2.address)).to.be.revertedWith(
        'ZirconPair: User not approved'
    )
    await pair.addApprovedUser(account2.address)
    await pair.removeApprovedUser(account2.address)
  });
})

describe("Pylon", () => {
  it('should add float liquidity', function () {

  });
})
