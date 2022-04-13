// TODO: clean this...
const { expect } = require("chai");
const { ethers } = require('hardhat');
const assert = require("assert");
const {BigNumber} = require("ethers");
const {expandTo18Decimals} = require("./shared/utils");
const {coreFixtures} = require("./shared/fixtures");
const TEST_ADDRESSES = [
    '0x1000000000000000000000000000000000000000',
    '0x2000000000000000000000000000000000000000'
]
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
async function getOutputAmount(input, inputReserves, outputReserves) {
    let amountWithFees = input.mul(ethers.BigNumber.from("977"))
    let numerator = amountWithFees.mul(outputReserves)
    let denominator = amountWithFees.add(inputReserves.mul(ethers.BigNumber.from("1000")))
    return numerator.div(denominator)
}

// TODO: See case where we have a big dump
describe("Pylon", () => {
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
        [5, 10, '4749999999999999', '4749999999999999','149999999999999002','99999999999999000', false],
        [10, 5, '4749999999999999', '4749999999999999','99999999999999000', '149999999999999000', true],
        [5, 10, '2374999999999999', '9499999999999999','49999999999999000', '149999999999999000', true],
        [10, 10, '9500000000000000', '4750000000000000','199999999999999000', '99999999999999000', false],
        [1000, 1000, '475000000000000000', '950000000000000000','9999999999999999000', '19999999999999999000', true],
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
            console.log("Mint test token0Amount: ", token0Amount);
            // Let's start the pylon
            await pylonInstance.initPylon(account.address)
            // Transferring some liquidity to pylon
            // let pylonRes = await pylonInstance.getSyncReserves()
            // let pairRes = await pair.getReserves()

            if (isAnchor) {
                let t = token0Amount.div(100)
                await token1.transfer(pylonInstance.address, t)
            }else{
                let t = token1Amount.div(100)
                await token0.transfer(pylonInstance.address, t)
            }

            // Minting some float/anchor tokens
            await expect(pylonInstance.mintPoolTokens(account.address, isAnchor))
                .to.emit(pylonInstance, 'PylonUpdate')
                .withArgs(expectedRes0, expectedRes1);
            // Let's check the balances, float
            // expect(await pylonInstance.gammaMulDecimals()).to.eq(ethers.BigNumber.from('1000000000000000000'));
            expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(expectedOutputAmount1);

            expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(expectedOutputAmount0);
            // Anchor
        })
    })  // Let's try to calculate some cases for pylon

    it('Test Creating Pylon With Unbalanced Quantities', async function () {
        let token0Amount = expandTo18Decimals(1700)
        let token1Amount = expandTo18Decimals(5300)

        await addLiquidity(token0Amount, token1Amount)
        // Let's transfer some tokens to the Pylon
        await token0.transfer(pylonInstance.address, token0Amount.div(100))
        await token1.transfer(pylonInstance.address, token1Amount.div(11))
        //Let's initialize the Pylon, this should call two sync
        await pylonInstance.initPylon(account.address)

        await token0.transfer(pylonInstance.address, expandTo18Decimals(4))
        await token1.transfer(pylonInstance.address, expandTo18Decimals(4))
        await expect(pylonInstance.mintPoolTokens(account.address, false))
        let gamma = await pylonInstance.gammaMulDecimals()

        await expect(gamma).to.eq(ethers.BigNumber.from("500000000000000000"))

        await expect(pylonInstance.mintPoolTokens(account.address, true))
        gamma = await pylonInstance.gammaMulDecimals()
        await expect(gamma).to.eq(ethers.BigNumber.from("500000000000000000"))

        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("105954545454545453652"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("481818181818181817181"))

    });

    it('should add float/anchor liquidity', async function () {
        // Adding some tokens and minting
        // here we initially the pool
        await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        // Let's check if pair tokens and poolToken have b000een given correctly...
        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("259234808523880957500"))
        // On init the tokens sent to the pylon exceeds maxSync
        // So we have less tokens
        // We donated some tokens to the pylon over there
        // Let's check that we have the current quantities...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("154545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("481818181818181817181"))
        // Let's put some minor quantities into the pylon
        // it shouldn't mint any pool tokens for pylon, just increase reserves on pylon
        // First Float...
        const token0Amount = expandTo18Decimals(4)
        await token0.transfer(pylonInstance.address, token0Amount)
        await expect(pylonInstance.mintPoolTokens(account.address, false))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from('11340909090909090910'), ethers.BigNumber.from('22886363636363636363'));
        // Then Anchor...
        await token1.transfer(pylonInstance.address, token0Amount)
        await expect(pylonInstance.mintPoolTokens(account.address, true))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from('10077208404802744427'), ethers.BigNumber.from('22946590909090909090'))
        // Same pair tokens as before on pylon..

        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("262148304001010076401"))
        // We increase by 4 the Anchor and Float share...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("158545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("485818181818181817181"))
        // Ok Let's send some higher random quantities to the pylon
        // Here we increase the float token
        // The pylon has to donate the exceeding tokens to the pair
        // The pylon shouldn't mint any pair tokens yet...
        const newAmount0 = expandTo18Decimals(5)
        await token0.transfer(pylonInstance.address, newAmount0)
        await expect(pylonInstance.mintPoolTokens(account.address, false))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from("14846824614065180102"), ethers.BigNumber.from('22946590909090909090'))
        // Same pair tokens as before on pylon...
        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("262351073941888117774"))

        // Let's send some anchor token
        // Pylon should mint some pair tokens
        const newAmount1 = expandTo18Decimals(8)
        await token1.transfer(pylonInstance.address, newAmount1)
        await expect(pylonInstance.mintPoolTokens(account.address, true))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from("12348941066927392118"), ethers.BigNumber.from("23160042091378079676"))
        // We increase pylon float reserves by 242.5*1e18 and we minted that quantity for the user
        // And we donated to the pair 257.5*1e18
        // For a total of 500*1e18
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("163545454545454544454"))
        // We increased pylon anchor reserves by 764 and we minted that quantity for the user
        // And we didn't donate...
        // We minted some more pool shares for the pylon for 165*1e18 float and 516*1e18 anchor
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("493818181818181817181"))
        // And here Pylon increased the pair share 516*totalSupply/reserves1 ->
        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from("266761276299396760383"));
    });

    it('should test fees on sync', async () => {
        await factoryInstance.setFeeTo(account2.address)
        await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))

        const token0Amount = expandTo18Decimals(4)
        await token0.transfer(pylonInstance.address, token0Amount)
        await expect(pylonInstance.mintPoolTokens(account.address, false))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from('11340909090909090910'), ethers.BigNumber.from('22886363636363636363'));
        // Then Anchor...
        await token1.transfer(pylonInstance.address, token0Amount)
        await expect(pylonInstance.mintPoolTokens(account.address, true))
            .to.emit(pylonInstance, 'MintAT')
            .to.emit(pylonInstance, 'PylonUpdate')
            .withArgs(ethers.BigNumber.from('10077208404802744427'), ethers.BigNumber.from('22946590909090909090'))
        // We increase by 4 the Anchor and Float share...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("150618181818181817232"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("461527272727272726322"))
        // Let's check the fees...
        expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("7927272727272727222"))
        expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("24290909090909090859"))


    })

    it('should test fees on async 100', async () => {
        await factoryInstance.setFeeTo(account2.address)
        await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))

        const token0Amount = expandTo18Decimals(1)
        await token0.transfer(pylonInstance.address, token0Amount)
        await pylonInstance.mintAsync100(account.address, false)
        // Then Anchor...
        await token1.transfer(pylonInstance.address, token0Amount)
        await pylonInstance.mintAsync100(account.address, true)
        // We increase by 4 the Anchor and Float share...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("147814912776871850369"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("458724186415182923591"))
        // Let's check the fees...
        expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("7727272727272727222"))
        expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("24090909090909090859"))
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
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("149255917667238421005"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("465327272727272726322"))
        // Let's check the fees...
        expect(await poolTokenInstance0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("7855574614065180052"))
        expect(await poolTokenInstance1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("24490909090909090859"))
    })

    const syncTestCase = [
        [2, 5, 10, '43181818181818181', '43181818181818181','974999999999998990','909090909090908090', false],
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
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('363636363636362636'))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('747272727272726272'))
        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from('489832152058316516'))

        let atb = await poolTokenInstance1.balanceOf(account.address);
        await poolTokenInstance1.transfer(pylonInstance.address, atb);
        await pylonInstance.burn(account2.address, true)

        console.log(await token1.balanceOf(account2.address));
    });

    it('creating two pylons', async function () {
        await init(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        await factoryPylonInstance.addPylon(pair.address, token1.address, token0.address);
        let pylonAddress = await factoryPylonInstance.getPylon(token1.address, token0.address)

        let zPylon = await ethers.getContractFactory('ZirconPylon')
        let newPylonInstance = await zPylon.attach(pylonAddress);
        // Let's transfer some tokens to the Pylon
        await token0.transfer(newPylonInstance.address, expandTo18Decimals(17))
        await token1.transfer(newPylonInstance.address, expandTo18Decimals(  53))
        //Let's initialize the Pylon, this should call two sync
        await newPylonInstance.initPylon(account.address, overrides)
        // TODO: make sonme checks here, think if there is some way of concurrency between pylons
    });

    // TODO: Do test extracting liquidity here
    it('sync', async function () {
        // Initializing
        await init(expandTo18Decimals(10), expandTo18Decimals(  100))

        // VAB at the beginning is equal to the minted pool tokens
        let vab = await pylonInstance.virtualAnchorBalance();
        console.log(vab)
        expect(vab).to.eq(ethers.BigNumber.from('9090909090909090909'))
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
        expect(vfb).to.eq(ethers.BigNumber.from('947728772470068004'))
        expect(vab2).to.eq(ethers.BigNumber.from('9394220164340522812'))
        // Let's mint some LP Tokens
        // no fee changes so vab & vfb should remain the same
        await addLiquidity(expandTo18Decimals(1), expandTo18Decimals(  10))
        let vfb3 = await pylonInstance.virtualFloatBalance();
        let vab3 = await pylonInstance.virtualAnchorBalance();
        expect(vfb3).to.eq(ethers.BigNumber.from('947728772470068004'))
        expect(vab3).to.eq(ethers.BigNumber.from('9394220164340522812'))

        await token1.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, true)

        await token1.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, true)
    })
    it('sync2', async function () {
        // Initializing
        await init(expandTo18Decimals(10), expandTo18Decimals(  100))

        // VAB at the beginning is equal to the minted pool tokens
        let vab = await pylonInstance.virtualAnchorBalance();
        console.log(vab)
        expect(vab).to.eq(ethers.BigNumber.from('9090909090909090909'))
        // Time to swap, let's generate some fees
        await token0.transfer(pair.address, expandTo18Decimals(1))
        await pair.swap(0, ethers.BigNumber.from('1662497915624478906'), account.address, '0x', overrides)
        // Minting tokens is going to trigger a change in the VAB & VFB so let's check
        const newAmount0 = ethers.BigNumber.from('10000000000000000')
        await token0.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, false)

        // So here we increase our vab and vfb
        let vfb = await pylonInstance.virtualFloatBalance();
        let vab2 = await pylonInstance.virtualAnchorBalance();
        expect(vfb).to.eq(ethers.BigNumber.from('952728772470068004'))
        expect(vab2).to.eq(ethers.BigNumber.from('9394220164340522812'))
        // Let's mint some LP Tokens
        // no fee changes so vab & vfb should remain the same
        await addLiquidity(expandTo18Decimals(1), expandTo18Decimals(  10))
        let vfb3 = await pylonInstance.virtualFloatBalance();
        let vab3 = await pylonInstance.virtualAnchorBalance();
        expect(vfb3).to.eq(ethers.BigNumber.from('952728772470068004'))
        expect(vab3).to.eq(ethers.BigNumber.from('9394220164340522812'))

        await token0.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, false)

        await token0.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, false)
    })
    it('sync3', async function () {
        // Initializing
        await init(expandTo18Decimals(10), expandTo18Decimals(  100))

        // VAB at the beginning is equal to the minted pool tokens
        let vab = await pylonInstance.virtualAnchorBalance();
        console.log(vab)
        expect(vab).to.eq(ethers.BigNumber.from('9090909090909090909'))
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
        expect(vfb).to.eq(ethers.BigNumber.from('947728772470068004'))
        expect(vab2).to.eq(ethers.BigNumber.from('9394220164340522812'))
        // Let's mint some LP Tokens
        // no fee changes so vab & vfb should remain the same
        await addLiquidity(expandTo18Decimals(1), expandTo18Decimals(  10))
        let vfb3 = await pylonInstance.virtualFloatBalance();
        let vab3 = await pylonInstance.virtualAnchorBalance();
        expect(vfb3).to.eq(ethers.BigNumber.from('947728772470068004'))
        expect(vab3).to.eq(ethers.BigNumber.from('9394220164340522812'))


        console.log("Sync3 Transferring newAmount0 for Async:", newAmount0)
        // await token0.transfer(pylonInstance.address, newAmount0)
        // await token1.transfer(pylonInstance.address, newAmount0)
        let ftb = await poolTokenInstance1.balanceOf(account.address)
        console.log(ftb.div(2))
        await poolTokenInstance1.transfer(pylonInstance.address, ftb.div(2))
        await pylonInstance.burn(account2.address, true)


        console.log("Sync3 Transferring newAmount0 for Sync:", newAmount0)
        await token1.transfer(pylonInstance.address, newAmount0)
        await pylonInstance.mintPoolTokens(account.address, true)
    })

    it('should burn anchor liquidity', async function () {
        console.log("Beginning anchor burn test");
        console.log(await token0.balanceOf(account2.address))
        console.log(await token1.balanceOf(account2.address))
        let token1Amount = expandTo18Decimals(  10)
        let token0Amount = expandTo18Decimals(5)

        let floatSum = token0Amount.div(11)
        let anchorSum = token1Amount.div(220).add(token1Amount.div(11))

        //Pylon init with 1/11 of token amounts into pylon.
        await init(token0Amount, token1Amount)


        // Minting some float/anchor tokens (1/20 of Pylon)
        await token1.transfer(pylonInstance.address, token1Amount.div(220))
        console.log("Anchors sent for minting: ", token1Amount.div(220))
        let initialPTS = await poolTokenInstance1.balanceOf(account.address);
        console.log("initialPTS: ", initialPTS);
        await pylonInstance.mintPoolTokens(account.address, true);



        //Initiating burn. This burns the 1/20 of Anchors sent before.
        let ptb = await poolTokenInstance1.balanceOf(account.address);

        console.log("ptb: ", ptb);
        let liquidityMinted = ptb.sub(initialPTS);
        console.log("liquidityMinted: ", liquidityMinted);
        await poolTokenInstance1.transfer(pylonInstance.address, liquidityMinted)
        await pylonInstance.burn(account2.address, true) //Burns to an account2


        console.log("initialFloat", floatSum)
        console.log("initialAnchor", anchorSum)
        console.log("floatBalance (should be 0)", await token0.balanceOf(account2.address))
        console.log("anchorBalance (should be roughly 1/20 of token1 minus fees and slippage)", await token1.balanceOf(account2.address))

        ptb = await poolTokenInstance0.balanceOf(account.address)
        expect(ptb).to.eq(ethers.BigNumber.from("454545454545453545"))

        //Burns half of the floats now
        let ftb = await poolTokenInstance0.balanceOf(account.address)
        await poolTokenInstance0.transfer(pylonInstance.address, ftb.div(2))

        await pylonInstance.burn(account2.address, false)
        console.log("Burn tests complete\ninitialFloat", floatSum)
        console.log("initialAnchor", anchorSum)
        console.log("Account2 Float (1/20 of token1 minus slippage)", await token0.balanceOf(account2.address))
        console.log("Account2 Anchor (same as before)", await token1.balanceOf(account2.address))
        //45454545454545454
        //45454545454545454
        //954545454545454544

        expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("220236528852723118"))
        expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("45454545454545454"))

        await token0.transfer(pylonInstance.address, token0Amount.div(220))
        await pylonInstance.mintPoolTokens(account.address, false);

        ptb = await poolTokenInstance0.balanceOf(account.address)
        //249999999999999500
        //454545454545453545
        expect(ptb).to.eq(ethers.BigNumber.from("249999999999999500"))
    })

    it('should burn async', async function () {
        let tokenAmount = expandTo18Decimals(  10)
        await init(expandTo18Decimals(5), tokenAmount)
        // Minting some float/anchor tokens
        let ptb = await poolTokenInstance1.balanceOf(account.address)

        expect(ptb).to.eq(ethers.BigNumber.from("909090909090908090"))

        await token1.transfer(pylonInstance.address, tokenAmount.div(220))
        await pylonInstance.mintPoolTokens(account.address, true);
        ptb = await poolTokenInstance1.balanceOf(account.address)

        expect(ptb).to.eq(ethers.BigNumber.from("954545454545453544"))
        await poolTokenInstance1.transfer(pylonInstance.address, ptb.div(2))
        await pylonInstance.burnAsync(account2.address, true)

        expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("113902336805269332"))
        expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("227852321523864441"))

        //Anchor burn is a bit sussy but mostly right (amounts are a weird percentage but close to what you'd expect. Maybe it's the fee?)

        let ftb = await poolTokenInstance0.balanceOf(account.address)
        await poolTokenInstance0.transfer(pylonInstance.address, ftb.div(2))
        await pylonInstance.burnAsync(account2.address, false)

        expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("228939119231152225"))
        expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from("458216168623073120"))

        await token1.transfer(pylonInstance.address, tokenAmount.div(220))
        await pylonInstance.mintPoolTokens(account.address, true);

        ptb = await poolTokenInstance1.balanceOf(account.address)
        expect(ptb).to.eq(ethers.BigNumber.from("522727272727272226"))
    })

    it('should burn after init', async function () {
        let tokenAmount = expandTo18Decimals(10)
        await init(expandTo18Decimals(5), tokenAmount)
        let ftb = await poolTokenInstance0.balanceOf(account.address)
        await poolTokenInstance0.transfer(pylonInstance.address, ftb)

        await pylonInstance.burn(account2.address, false)

        let ptb = await poolTokenInstance1.balanceOf(account.address)
        await poolTokenInstance1.transfer(pylonInstance.address, ptb)

        await pylonInstance.burn(account2.address, true)
    })
    it('should add async liquidity', async function () {
        // Let's initialize the pool and pylon
        await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        // Let's transfer some tokens to the Pylon
        await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
        await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
        //Let's initialize the Pylon, this should call two sync
        await pylonInstance.initPylon(account.address)
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("154545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq((ethers.BigNumber.from("481818181818181817181")))


        // Let's send some tokens
        const token0Amount = expandTo18Decimals(25)
        await token0.transfer(pylonInstance.address, token0Amount)
        await token1.transfer(pylonInstance.address, token0Amount)
        // Let's try to mint async
        await pylonInstance.mintAsync(account.address, false);
        // We should receive float tokens and pylon should've minted some pair shares
        // Let's check...
        console.log(await poolTokenInstance0.balanceOf(account.address))
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("170583190394511148227"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("481818181818181817181"))

        // Now let's test to receive some anchor tokens
        await token0.transfer(pylonInstance.address, token0Amount)
        await token1.transfer(pylonInstance.address, token0Amount)
        await pylonInstance.mintAsync(account.address, true);
        // Let's check...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("170583190394511148227"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('531818181818181817181'))
    });

    it('should add async liquidity 100', async function () {
        // Let's initialize the pool and pylon
        console.log("New Test: Async Liquidity 100%")
        await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        // Let's transfer some tokens to the Pylon
        await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
        await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
        //Let's initialize the Pylon, this should call two sync
        await pylonInstance.initPylon(account.address)
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("154545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('481818181818181817181'))

        // Let's send some tokens
        const token0Amount = expandTo18Decimals(50)
        await token0.transfer(pylonInstance.address, token0Amount)
        // await token1.transfer(pylonInstance.address, token0Amount)
        // Let's try to mint async

        await pylonInstance.mintAsync100(account.address, false);
        // We should receive float tokens and pylon should've minted some pair shares
        // Let's check...
        console.log(await poolTokenInstance0.balanceOf(account.address))
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("203731628833642390736"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('481818181818181817181'))

        // Now let's test to receive some anchor tokens
        // await token0.transfer(pylonInstance.address, token0Amount)
        await token1.transfer(pylonInstance.address, token0Amount)
        await pylonInstance.mintAsync100(account.address, true);
        // Let's check...
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("203731628833642390736"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('531453313070866669640'))
    });

    it('should dump::float', async function () {
        // Let's initialize the pool and pylon
        await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        // Let's transfer some tokens to the Pylon
        await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
        await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
        //Let's initialize the Pylon, this should call two sync
        await pylonInstance.initPylon(account.address)
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("154545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('481818181818181817181'))

        let vab = await pylonInstance.virtualAnchorBalance();
        let vfb = await pylonInstance.virtualFloatBalance();
        let gamma = await pylonInstance.gammaMulDecimals();
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)
        console.log("totalSupply", await poolTokenInstance0.totalSupply())

        let ftb = await poolTokenInstance0.balanceOf(account.address)
        await poolTokenInstance0.transfer(pylonInstance.address, ftb)

        await pylonInstance.burn(account2.address, false)
        let input = expandTo18Decimals(100)
        await token0.transfer(pair.address, input)
        let reserves = await pair.getReserves()
        console.log("hey", reserves[0])
        //let outcome = (input.mul(reserves[1]).div(reserves[0])).sub(ethers.BigNumber.from('1000000000000000000'))
        let outcome = getOutputAmount(input, reserves[0],reserves[1])
        console.log("out", outcome)
        await token0.transfer(pair.address, input)
        await pair.swap(0, outcome, account.address, '0x', overrides)
        vab = await pylonInstance.virtualAnchorBalance();
        vfb = await pylonInstance.virtualFloatBalance();
        gamma = await pylonInstance.gammaMulDecimals();
        console.log("totalsupply", await poolTokenInstance0.totalSupply())
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)
        await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))

        await expect(pylonInstance.mintPoolTokens(account.address, false))


        //expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("159325210871602624179"))

        vab = await pylonInstance.virtualAnchorBalance();
        vfb = await pylonInstance.virtualFloatBalance();
        gamma = await pylonInstance.gammaMulDecimals();
        console.log("totalsupply", await poolTokenInstance0.totalSupply())
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)
    });
    it('should dump::anchor', async function () {
        // Let's initialize the pool and pylon
        await addLiquidity(expandTo18Decimals(1700), expandTo18Decimals(  5300))
        // Let's transfer some tokens to the Pylon
        await token0.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))
        await token1.transfer(pylonInstance.address, expandTo18Decimals(  5300).div(11))
        //Let's initialize the Pylon, this should call two sync
        await pylonInstance.initPylon(account.address)
        expect(await poolTokenInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from("154545454545454544454"))
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('481818181818181817181'))

        let vab = await pylonInstance.virtualAnchorBalance();
        let vfb = await pylonInstance.virtualFloatBalance();
        let gamma = await pylonInstance.gammaMulDecimals();
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)
        console.log("totalSupply", await poolTokenInstance1.totalSupply())

        let ftb = await poolTokenInstance1.balanceOf(account.address)
        await poolTokenInstance1.transfer(pylonInstance.address, ftb)

        await pylonInstance.burn(account2.address, true)
        let input = expandTo18Decimals(100)
        await token1.transfer(pair.address, input)
        let reserves = await pair.getReserves()
        let outcome = getOutputAmount(input, reserves[0],reserves[1])
        await token0.transfer(pair.address, input)
        await pair.swap(0, outcome, account.address, '0x', overrides)

        vab = await pylonInstance.virtualAnchorBalance();
        vfb = await pylonInstance.virtualFloatBalance();
        gamma = await pylonInstance.gammaMulDecimals();

        console.log("totalsupply", await poolTokenInstance1.totalSupply())
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)

        await token1.transfer(pylonInstance.address, expandTo18Decimals(1700).div(11))

        await expect(pylonInstance.mintPoolTokens(account.address, true))


        // expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from("159325210871602624179"))

        vab = await pylonInstance.virtualAnchorBalance();
        vfb = await pylonInstance.virtualFloatBalance();
        gamma = await pylonInstance.gammaMulDecimals();
        console.log("mintedTokens", await poolTokenInstance1.balanceOf(account.address))
        console.log("totalsupply", await poolTokenInstance0.totalSupply())
        console.log("vab", vab)
        console.log("vfb", vfb)
        console.log("gamma", gamma)
    });

})
