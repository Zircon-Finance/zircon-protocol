const { expect } = require("chai");
const { ethers } = require('hardhat');
const {expandTo18Decimals} = require("./shared/utils");
const {coreFixtures} = require("./shared/fixtures");

let factoryPylonInstance,  token0, token1,
    pylonInstance, poolTokenInstance0, poolTokenInstance1,
    factoryInstance, deployerAddress, account2, account,
    pair;

const MINIMUM_LIQUIDITY = ethers.BigNumber.from(10).pow(3)
const overrides = {
  gasLimit: 9999999
}

async function addLiquidity(token0Amount, token1Amount) {
  await token0.transfer(pair.address, token0Amount)
  await token1.transfer(pair.address, token1Amount)
  await pair.mint(account.address)
}



describe("Pair", () => {
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
  // Same as Uniswap v2 - CORE
  it('mint', async () => {

    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)

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
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount)
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount)
    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount)
    expect(reserves[1]).to.eq(token1Amount)
  })

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

      await token0.transfer(pair.address, swapAmount)
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
    await token0.transfer(pair.address, swapAmount)
    await expect(pair.swap(0, expectedOutputAmount, account.address, '0x', overrides))
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'Swap')
        .withArgs(account.address, swapAmount, 0, 0, expectedOutputAmount, account.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount))
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount))
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount))
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await token1.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
  })

  it('swap:token1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('453305446940074565')
    await token1.transfer(pair.address, swapAmount)
    await expect(pair.swap(expectedOutputAmount, 0, account.address, '0x', overrides))
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.sub(expectedOutputAmount), token1Amount.add(swapAmount))
        .to.emit(pair, 'Swap')
        .withArgs(account.address, 0, swapAmount, expectedOutputAmount, 0, account.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.sub(expectedOutputAmount))
    expect(reserves[1]).to.eq(token1Amount.add(swapAmount))
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.sub(expectedOutputAmount))
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.add(swapAmount))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(token0Amount).add(expectedOutputAmount))
    expect(await token1.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(token1Amount).sub(swapAmount))
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
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, account.address, token0Amount.sub(1000))
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, account.address, token1Amount.sub(1000))
        .to.emit(pair, 'Sync')
        .withArgs(1000, 1000)
        .to.emit(pair, 'Burn')
        .withArgs(account.address, token0Amount.sub(1000), token1Amount.sub(1000), account.address)

    expect(await pair.balanceOf(account.address)).to.eq(0)
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
    expect(await token0.balanceOf(pair.address)).to.eq(1000)
    expect(await token1.balanceOf(pair.address)).to.eq(1000)
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(account.address)).to.eq(totalSupplyToken0.sub(1000))
    expect(await token1.balanceOf(account.address)).to.eq(totalSupplyToken1.sub(1000))
  })

  it('feeTo:off', async () => {
    const token0Amount = expandTo18Decimals(1000)
    const token1Amount = expandTo18Decimals(1000)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('996006981039903216')
    await token1.transfer(pair.address, swapAmount)
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
    await token1.transfer(pair.address, swapAmount)
    await pair.swap(expectedOutputAmount, 0, account.address, '0x', overrides)

    const expectedLiquidity = expandTo18Decimals(1000)
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
    await pair.burn(account.address, overrides)
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY.add('249750499251388'))
    expect(await pair.balanceOf(account2.address)).to.eq('249750499251388')

    // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
    // ...because the initial liquidity amounts were equal
    expect(await token0.balanceOf(pair.address)).to.eq(ethers.BigNumber.from(1000).add('249501683697445'))
    expect(await token1.balanceOf(pair.address)).to.eq(ethers.BigNumber.from(1000).add('250000187312969'))
  })


})
