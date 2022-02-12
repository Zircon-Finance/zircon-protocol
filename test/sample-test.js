// TODO: clean this...
const { expect } = require("chai");
const { ethers } = require('hardhat');
const assert = require("assert");
const {BigNumber} = require("ethers");
const TEST_ADDRESSES = [
  '0x1000000000000000000000000000000000000000',
  '0x2000000000000000000000000000000000000000'
]
let factory, factoryPylonInstance,  token0, token1,
    pylonInstance, poolTokenInstance0, poolTokenInstance1,
    factoryInstance, deployerAddress, account2, account,
    lpAddress, pair;

const MINIMUM_LIQUIDITY = ethers.BigNumber.from(10).pow(3)
const overrides = {
  gasLimit: 9999999
}
function expandTo18Decimals(n) {return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18))}

async function addLiquidity(token0Amount, token1Amount) {
  await token0.transfer(pair.address, token0Amount)
  await token1.transfer(pair.address, token1Amount)
  await pair.mint(account.address)
}

beforeEach(async () => {
  [account, account2] = await ethers.getSigners();
  deployerAddress = account.address;

  factory = await ethers.getContractFactory('ZirconFactory');
  factoryInstance = await factory.deploy(deployerAddress);

  let factoryPylon = await ethers.getContractFactory('ZirconPylonFactory');
  factoryPylonInstance = await factoryPylon.deploy(expandTo18Decimals(5), expandTo18Decimals(3),
      factoryInstance.address);

  // Deploy Tokens
  let tok1 = await ethers.getContractFactory('Token');
  let tok1Instance = await tok1.deploy('Token1', 'TOK1');
  let tok2 = await ethers.getContractFactory('Token');
  let tok2Instance = await tok2.deploy('Token2', 'TOK2');

  await factoryInstance.createPair(tok1Instance.address, tok2Instance.address);
  lpAddress = await factoryInstance.getPair(tok1Instance.address, tok2Instance.address)
  let pairContract = await ethers.getContractFactory("ZirconPair");
  pair = await pairContract.attach(lpAddress);

  const token0Address = await pair.token0();
  token0 = tok1Instance.address === token0Address ? tok1Instance : tok2Instance
  token1 = tok2Instance.address === token0Address ? tok1Instance : tok2Instance

  await factoryPylonInstance.addPylon(lpAddress, token0.address, token1.address);
  let pylonAddress = await factoryPylonInstance.getPylon(token0.address, token1.address)

  let zPylon = await ethers.getContractFactory('ZirconPylon')
  let poolToken1 = await ethers.getContractFactory('ZirconPoolToken')
  let poolToken2 = await ethers.getContractFactory('ZirconPoolToken')
  pylonInstance = await zPylon.attach(pylonAddress);

  let poolAddress2 = await pylonInstance.anchorPoolToken();

  let poolAddress1 = await pylonInstance.floatPoolToken();

  poolTokenInstance0 = poolToken1.attach(poolAddress1)
  poolTokenInstance1 = poolToken2.attach(poolAddress2)


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

describe("Pair", () => {

  // Same as Uniswap v2 - CORE
  it('mint', async () => {

    const token0Amount = expandTo18Decimals(1)
    const token1Amount = expandTo18Decimals(4)
    await token0.transfer(lpAddress, token0Amount)
    await token1.transfer(lpAddress, token1Amount)

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

  it('swapNoFee:token0', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('1666666666666666666')
    await token0.transfer(pair.address, swapAmount)
    await expect(pair.swapNoFee(0, expectedOutputAmount, account.address, '0x', overrides))
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'SwapNoFee')
        .withArgs(account.address, 0, expectedOutputAmount, account.address)

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
  it('swapNoFee:token1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = ethers.BigNumber.from('454545454545454545')
    await token1.transfer(pair.address, swapAmount)
    await expect(pair.swapNoFee(expectedOutputAmount, 0, account.address, '0x', overrides))
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, account.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.sub(expectedOutputAmount), token1Amount.add(swapAmount))
        .to.emit(pair, 'SwapNoFee')
        .withArgs(account.address, expectedOutputAmount, 0, account.address)

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


  it('should add users', async function () {
    await expect(pair.removeApprovedUser(account2.address)).to.be.revertedWith(
        'ZirconPair: User not approved'
    )
    await pair.addApprovedUser(account2.address)
    await pair.removeApprovedUser(account2.address)
  });
})

// TODO: Put correct events emitted from Pylon SC
// TODO: Create Test async 100%
// TODO: See case where we have a big dump
// TODO: Extract Liquidity Tests
describe("Pylon", () => {

  const init = async (token0Amount, token1Amount) => {
    // Let's initialize the Pool, inserting some liquidity in it
    await addLiquidity(token0Amount, token1Amount)
    // Let's transfer some tokens to the Pylon
    await token0.transfer(pylonInstance.address, token0Amount.div(11))
    await token1.transfer(pylonInstance.address, token1Amount.div(11))
    //Let's initialize the Pylon, this should call two sync
    await pylonInstance.initPylon(account.address)
  }
  // Let's try to calculate some cases for pylon
  //TODO: recheck the values, they are way to similar
  const mintTestCases = [
    [5, 10, '499999999999999990', '100000000000000000','10450000000000044','1000000000000000000', false],
    [10, 5, '100000000000000000', '499999999999999990','10000000000000000', '1900000000000000897', true],
    [5, 10, '50000000000000000', '999999999999999990','10000000000000000', '1900000000000000898', true],
    [10, 10, '999999999999999990', '100000000000000000','10450000000000044', '1000000000000000000', false],
    [1000, 1000, '10000000000000000000', '99999999999999999990','10000000000000000', '1900000000000000899', true],
 ].map(a => a.map(n => (typeof n  === "boolean" ? n : typeof n === 'string' ? ethers.BigNumber.from(n) : expandTo18Decimals(n))))
  mintTestCases.forEach((mintCase, i) => {
    it(`mintPylon:${i}`, async () => {
      const [token0Amount, token1Amount, expectedRes0, expectedRes1, expectedOutputAmount0, expectedOutputAmount1, isAnchor] = mintCase
      // Add some liquidity to the Pair...
      await addLiquidity(token0Amount, token1Amount)
      // Transferring some tokens
      let maxSync = await pylonInstance.maximumPercentageSync()
      await token0.transfer(pylonInstance.address, token0Amount.div(100))
      await token1.transfer(pylonInstance.address, token1Amount.div(100))
      // Let's start the pylon
      await pylonInstance.initPylon(account.address)
      // Transferring some liquidity to pylon
      let pylonRes = await pylonInstance.getSyncReserves()
      let pairRes = await pair.getReserves()

      if (isAnchor) {
        let t = (pairRes[1].mul(maxSync).div(100)).sub(pylonRes[1]).sub(10)
        await token1.transfer(pylonInstance.address, t)
      }else{
        let t = (pairRes[0].mul(maxSync).div(100)).sub(pylonRes[0]).sub(10)
        await token0.transfer(pylonInstance.address, t)
      }

      // Minting some float/anchor tokens
      await expect(pylonInstance.mintPoolTokens(account.address, isAnchor))
          .to.emit(pylonInstance, 'PylonUpdate')
          .withArgs(expectedRes0, expectedRes1);
      // Let's check the balances, float
      expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expectedOutputAmount1);

      expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(expectedOutputAmount0);
      // Anchor
    })
  })  // Let's try to calculate some cases for pylon

  it('Sync LP Should fail exceeding max', async function () {
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))
    await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300))
    // Minting some float/anchor tokens
    await expect(pylonInstance.mintPoolTokens(account.address, true)).to.be.revertedWith(
        "ZP: Exceeds"
    )
  });

  it('should add float/anchor liquidity', async function () {
    // Adding some tokens and minting
    // here we initially the pool
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))
    // Let's check if pair tokens and poolToken have been given correctly...
    assert((await pair.balanceOf(pylonInstance.address)).eq(ethers.BigNumber.from("122795435616575190394")) )
    // On init the tokens sent to the pylon exceeds maxSync
    // So we have less tokens
    // We donated some tokens to the pylon over there
    // Let's check that we have the current quantities...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90909090909090909"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("1000000000000000000"))
    // Let's put some minor quantities into the pylon
    // it shouldn't mint any pool tokens for pylon, just increase reserves on pylon
    // First Float...
    const token0Amount = expandTo18Decimals(4)
    await token0.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintPoolTokens(account.address, false))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from('6954545454545454545'), ethers.BigNumber.from('10840909090909090908'));
    // Then Anchor...
    await token1.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintPoolTokens(account.address, true))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from('6954545454545454545'), ethers.BigNumber.from('14840909090909090908'))
    // Same pair tokens as before on pylon..

    expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("266786308805872655364"))
    // We increase by 4 the Anchor and Float share...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90999607987903627"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("1008233532934131744"))
    // Ok Let's send some higher random quantities to the pylon
    // Here we increase the float token
    // The pylon has to donate the exceeding tokens to the pair
    // The pylon shouldn't mint any pair tokens yet...
    const newAmount0 = expandTo18Decimals(5)
    await token0.transfer(pylonInstance.address, newAmount0)
    await expect(pylonInstance.mintPoolTokens(account.address, false))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from("11954545454545454545"), ethers.BigNumber.from('14840909090909090908'))
    // Same pair tokens as before on pylon...
    expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("266786308805872655364"))

    // Let's send some anchor token
    // Pylon should mint some pair tokens
    const newAmount1 = expandTo18Decimals(8)
    await token1.transfer(pylonInstance.address, newAmount1)
    await expect(pylonInstance.mintPoolTokens(account.address, true))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from("11954545454545454545"), ethers.BigNumber.from("22840909090909090908"))
    // We increase pylon float reserves by 242.5*1e18 and we minted that quantity for the user
    // And we donated to the pair 257.5*1e18
    // For a total of 500*1e18
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("91233020913024247"))
    // We increased pylon anchor reserves by 764 and we minted that quantity for the user
    // And we didn't donate...
    // We minted some more pool shares for the pylon for 165*1e18 float and 516*1e18 anchor
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("1024567213143668504"))
    // And here Pylon increased the pair share 516*totalSupply/reserves1 ->
    expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("266786308805872655364"));
  });

  it('should test fees on sync', async () => {
    await factoryInstance.setFeeTo(account2.address)
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))

    const token0Amount = expandTo18Decimals(4)
    await token0.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintPoolTokens(account.address, false))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from('6954545454545454545'), ethers.BigNumber.from('10840909090909090908'));
    // Then Anchor...
    await token1.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintPoolTokens(account.address, true))
        .to.emit(pylonInstance, 'MintAT')
        .to.emit(pylonInstance, 'PylonUpdate')
        .withArgs(ethers.BigNumber.from('6954545454545454545'), ethers.BigNumber.from('14840909090909090908'))
    // We increase by 4 the Anchor and Float share...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("86449627588508447"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("957821856287425157"))
    // Let's check the fees...
    expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("4549980399395180"))
    expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("50411676646706587"))


  })

  it('should test fees on async 100', async () => {
    await factoryInstance.setFeeTo(account2.address)
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))

    const token0Amount = expandTo18Decimals(4)
    await token0.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintAsync100(account.address, false))
    // Then Anchor...
    await token1.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintAsync100(account.address, true))
    // We increase by 4 the Anchor and Float share...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("86449627588508447"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("957821856287425157"))
    // Let's check the fees...
    expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("4549980399395180"))
    expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("50411676646706587"))
  })

  it('should test fees on async', async () => {
    await factoryInstance.setFeeTo(account2.address)
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))

    const token0Amount = expandTo18Decimals(4)
    await token0.transfer(pylonInstance.address, token0Amount)
    await token1.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintAsync(account.address, false))
    // Then Anchor...
    await token0.transfer(pylonInstance.address, token0Amount)
    await token1.transfer(pylonInstance.address, token0Amount)
    await expect(pylonInstance.mintAsync(account.address, true))
    // We increase by 4 the Anchor and Float share...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("86422959095777750"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("966603773584905676"))
    // Let's check the fees...
    expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("4545454545454545"))
    expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("50000000000000000"))
  })

  const syncTestCase = [
    [2, 5, 10, '20454545454545454', '20454545454545454','92989955118615111','1000000000000000000', false],
 ].map(a => a.map(n => (typeof n  === "boolean" ? n : typeof n === 'string' ? ethers.BigNumber.from(n) : expandTo18Decimals(n))))
  syncTestCase.forEach((mintCase, i) => {
    it(`syncPylon`, async () => {
      const [mint, token0Amount, token1Amount, expectedRes0, expectedRes1, expectedOutputAmount0, expectedOutputAmount1, isAnchor] = mintCase
      // Add some liquidity to the Pair...
      await addLiquidity(token0Amount, token1Amount)
      // Transferring some tokens
      let maxSync = await pylonInstance.maximumPercentageSync()

      await token0.transfer(pylonInstance.address, token0Amount.div(maxSync.toNumber()+1))
      await token1.transfer(pylonInstance.address, token1Amount.div(maxSync.toNumber()+1))
      // Let's start the pylon
      await pylonInstance.initPylon(account.address)
      // for (let i = 0; i < 10; i++){
        // Transferring some liquidity to pylon
      let pylonRes = await pylonInstance.getSyncReserves()
      let pairRes = await pair.getReserves()

      if (isAnchor) {
        let t = (pairRes[1].mul(maxSync).div(100)).sub(pylonRes[1]).sub(10)
        console.log(t)
        await token1.transfer(pylonInstance.address, t)
      }else{
        let t = (pairRes[0].mul(maxSync).div(100)).sub(pylonRes[0]).sub(10)
        console.log(t)
        await token0.transfer(pylonInstance.address, t)
      }
      // Minting some float/anchor tokens
      await expect(pylonInstance.mintPoolTokens(account.address, isAnchor))
          .to.emit(pylonInstance, 'PylonUpdate')
          .withArgs(expectedRes0, expectedRes1);
      console.log(await poolTokenInstance0.balanceOf(account.address))
      console.log(await poolTokenInstance1.balanceOf(account.address))
      // Let's check the balances, float
      expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(expectedOutputAmount0);
      // Anchor
      expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expectedOutputAmount1);
      // }
    })
  })

  it('should initialize pair from pylon', async function () {
    const token0Amount = expandTo18Decimals(4)
    const token1Amount = expandTo18Decimals(8)

    // Let's transfer some tokens to the Pylon
    let maxSync = await pylonInstance.maximumPercentageSync()
    await token0.transfer(pylonInstance.address, token0Amount.div(maxSync.toNumber()+1))
    await token1.transfer(pylonInstance.address, token1Amount.div(maxSync.toNumber()+1))
    //Let's initialize the Pylon, this should call two sync
    await pylonInstance.initPylon(account.address)
    // TODO: Should receive max float sync
    await token1.transfer(pylonInstance.address, token0Amount.div(200))
    // Minting some float/anchor tokens
    await pylonInstance.mintPoolTokens(account.address, true);

    expect(await token0.balanceOf(pair.address)).to.eq(ethers.BigNumber.from('346363636363636399'))
    expect(await token1.balanceOf(pair.address)).to.eq(ethers.BigNumber.from('692727272727272799'))

    let atb = await poolTokenInstance1.balanceOf(account.address);
    await poolTokenInstance1.transfer(pylonInstance.address, atb);
    await pylonInstance.burn(account2.address, true)

    console.log(await token1.balanceOf(account2.address));
  });

  it('creating two pylons', async function () {
    await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))
    await factoryPylonInstance.addPylon(lpAddress, token1.address, token0.address);
    let pylonAddress = await factoryPylonInstance.getPylon(token1.address, token0.address)

    let zPylon = await ethers.getContractFactory('ZirconPylon')
    let newPylonInstance = await zPylon.attach(pylonAddress);
    // Let's transfer some tokens to the Pylon
    await token0.transfer(newPylonInstance.address, expandTo18Decimals(17))
    await token1.transfer(newPylonInstance.address, expandTo18Decimals(  53))
    //Let's initialize the Pylon, this should call two sync
    await newPylonInstance.initPylon(account.address)
    // TODO: make sonme checks here, think if there is some way of concurrency between pylons
  });

  // TODO: Do test extracting liquidity here
  it('sync', async function () {
    // Initializing
    await init(expandTo18Decimals(5), expandTo18Decimals(  10))
    // VAB at the beginning is equal to the minted pool tokens
    let vab = await pylonInstance.virtualAnchorBalance();
    console.log(vab)
    expect(vab).to.eq(ethers.BigNumber.from('909090909090909090'))
    // Time to swap, let's generate some fees
    await token0.transfer(pair.address, expandTo18Decimals(1))
    await pair.swap(0, ethers.BigNumber.from('1662497915624478906'), account.address, '0x', overrides)
    // Minting tokens is going to trigger a change in the VAB & VFB so let's check
    const newAmount0 = ethers.BigNumber.from('5000000000000000')
    await token0.transfer(pylonInstance.address, newAmount0)
    await pylonInstance.mintPoolTokens(account.address, false)
    // So here we increase our vab and vfb
    let vfb = await pylonInstance.virtualFloatBalance();
    let vab2 = await pylonInstance.virtualAnchorBalance();
    expect(vfb).to.eq(ethers.BigNumber.from('459574189648471969'))
    expect(vab2).to.eq(ethers.BigNumber.from('909646379229805364'))
    // Let's mint some LP Tokens
    // no fee changes so vab & vfb should remain the same
    await addLiquidity(expandTo18Decimals(5), expandTo18Decimals(  10))
    let vfb3 = await pylonInstance.virtualFloatBalance();
    let vab3 = await pylonInstance.virtualAnchorBalance();
    expect(vfb3).to.eq(ethers.BigNumber.from('459574189648471969'))
    expect(vab3).to.eq(ethers.BigNumber.from('909646379229805364'))
  })


  // TODO: Recheck extraction results, are quite low
  it('should burn anchor liquidity', async function () {
    console.log(await token0.balanceOf(account2.address))
    console.log(await token1.balanceOf(account2.address))
    let token1Amount = expandTo18Decimals(  10)
    let token0Amount = expandTo18Decimals(5)

    let floatSum = token0Amount.div(11)
    let anchorSum = token1Amount.div(220).add(token1Amount.div(11))

    await init(token0Amount, token1Amount)
    await token1.transfer(pylonInstance.address, token1Amount.div(220))
    // Minting some float/anchor tokens
    await pylonInstance.mintPoolTokens(account.address, true);

    let ptb = await poolTokenInstance1.balanceOf(account.address)
    await poolTokenInstance1.transfer(pylonInstance.address, ptb)
    await pylonInstance.burn(account2.address, true)
    console.log("float", floatSum)
    console.log("anchor", anchorSum)
    console.log("float", await token0.balanceOf(account2.address))
    console.log("anchor", await token1.balanceOf(account2.address))

    let ftb = await poolTokenInstance0.balanceOf(account.address)
    await poolTokenInstance0.transfer(pylonInstance.address, ftb)

    await pylonInstance.burn(account2.address, false)
    console.log("float", floatSum)
    console.log("anchor", anchorSum)
    console.log("float", await token0.balanceOf(account2.address))
    console.log("anchor", await token1.balanceOf(account2.address))


    // expect(await token0.balanceOf(pair.address)).to.eq(token0Amount)
  })
  it('should burn async', async function () {
    let tokenAmount = expandTo18Decimals(  10)
    await init(expandTo18Decimals(5), tokenAmount)

    await token1.transfer(pylonInstance.address, tokenAmount.div(220))
    // Minting some float/anchor tokens
    await pylonInstance.mintPoolTokens(account.address, true);
    let ptb = await poolTokenInstance1.balanceOf(account.address)
    await poolTokenInstance1.transfer(pylonInstance.address, ptb)
    await pylonInstance.burnAsync(account2.address, true)

    expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("238089716406042708"))
    expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("477272727272726814"))


    let ftb = await poolTokenInstance0.balanceOf(account.address)
    await poolTokenInstance0.transfer(pylonInstance.address, ftb)
    await pylonInstance.burnAsync(account2.address, false)


    expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("346317585475747434"))
    expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("694225441642470958"))


  })


  it('should add async liquidity', async function () {
    // Let's initialize the pool and pylon
    await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
    // Let's transfer some tokens to the Pylon
    await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
    await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
    //Let's initialize the Pylon, this should call two sync
    await pylonInstance.initPylon(account.address)
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90909090909090909"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expandTo18Decimals(1))


    // Let's send some tokens
    const token0Amount = expandTo18Decimals(40)
    await token0.transfer(pylonInstance.address, token0Amount)
    await token1.transfer(pylonInstance.address, token0Amount)
    // Let's try to mint async
    await pylonInstance.mintAsync(account.address, false);
    // We should receive float tokens and pylon should've minted some pair shares
    // Let's check...
    console.log(await poolTokenInstance0.balanceOf(account.address))
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("91502318230504773"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expandTo18Decimals(1))

    // Now let's test to receive some anchor tokens
    await token0.transfer(pylonInstance.address, token0Amount)
    await token1.transfer(pylonInstance.address, token0Amount)
    await pylonInstance.mintAsync(account.address, true);
    // Let's check...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("91502318230504773"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1166037735849056769'))
  });

  it('should add async liquidity 100', async function () {
    // Let's initialize the pool and pylon
    await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
    // Let's transfer some tokens to the Pylon
    await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
    await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
    //Let's initialize the Pylon, this should call two sync
    await pylonInstance.initPylon(account.address)
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90909090909090909"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expandTo18Decimals(1))


    // Let's send some tokens
    const token0Amount = expandTo18Decimals(4)
    await token0.transfer(pylonInstance.address, token0Amount)
    // await token1.transfer(pylonInstance.address, token0Amount)
    // Let's try to mint async
    await pylonInstance.mintAsync100(account.address, false);
    // We should receive float tokens and pylon should've minted some pair shares
    // Let's check...
    console.log(await poolTokenInstance0.balanceOf(account.address))
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90999607987903627"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expandTo18Decimals(1))

    // Now let's test to receive some anchor tokens
    // await token0.transfer(pylonInstance.address, token0Amount)
    await token1.transfer(pylonInstance.address, token0Amount)
    await pylonInstance.mintAsync100(account.address, true);
    // Let's check...
    expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("90999607987903627"))
    expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1008233532934131744'))
  });

})
