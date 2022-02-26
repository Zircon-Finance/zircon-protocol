// TODO: clean this...
const { expect } = require("chai");
const { ethers, waffle } = require('hardhat');
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
    pair, router, WETH;

const MINIMUM_LIQUIDITY = ethers.BigNumber.from(10).pow(3)
const overrides = {
    gasLimit: 9999999
}

async function addLiquidity(token0Amount, token1Amount) {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(account.address)
}




describe("Pylon Router", () => {

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
        router = fixtures.routerInstance;
        WETH = fixtures.WETHInstance;
    });

    it('should initialize Pylon', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        expect(await pair.balanceOf(pylonInstance.address)).to.eq(ethers.BigNumber.from('1343502884254439296'))

    });

    it('should initialize Pylon WETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        // await WETH.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})

        //Let's get the instances of the new created Pylon and pair....
        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();
        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('999999999999999000'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1999999999999999000'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('50000000000000000'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('1343502884254439296'))
    });

    it('should revert when not initialized', async function () {
        await expect(router.addSyncLiquidity(
            token0.address,
            token1.address,
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256)).to.be.revertedWith(
            'ZPR: Pylon Not Initialized'
        )
    });

    it('should add sync liquidity', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        await router.addSyncLiquidity(
            token0.address,
            token1.address,
            ethers.BigNumber.from('44999999999999929'),
            true,
            account.address,
            ethers.constants.MaxUint256);
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2044999999999998929'))
    });

    it('should add sync liquidity ETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})
        await router.addSyncLiquidityETH(
            token0.address,
            ethers.BigNumber.from('44999999999999929'),
            true,
            false,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)});
        //expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1022004889975550110'))
        //Let's get the instances of the new created Pylon and pair....
        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();
        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('999999999999999000'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2042857142857142780'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('47499999999999964'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('1347038418160372084'))
    });

    it('should add async-100 liquidity', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        await router.addAsyncLiquidity100(
            token0.address,
            token1.address,
            ethers.BigNumber.from('44999999999999929'),
            true,
            account.address,
            ethers.constants.MaxUint256);
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2044341478829554712'))
    });

    it('should add async-100 liquidity ETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})
        await router.addAsyncLiquidity100ETH(
            token0.address,
            ethers.BigNumber.from('44999999999999929'),
            true,
            false,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)});
        //expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1022004889975550110'))
        //Let's get the instances of the new created Pylon and pair....
        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();
        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('999999999999999000'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2042857142857142780'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('50000000000000000'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('1343502884254439296'))
    });

    it('should add async liquidity', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        await router.addAsyncLiquidity(
            token0.address,
            token1.address,
            ethers.BigNumber.from('44999999999999929'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            account.address,
            ethers.constants.MaxUint256);
        expect(await poolTokenInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2045999999999998856'))
    });

    it('should add async liquidity ETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})

        await router.addAsyncLiquidityETH(
            token0.address,
            ethers.BigNumber.from('1022999999999998928'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)});

        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();
        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1022999999999999950'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2000000000000000000'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('50000000000000000'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('1359766340221729838'))

    });

    it('should remove liquidity', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await poolTokenInstance1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        await router.addAsyncLiquidity(
            token0.address,
            token1.address,
            ethers.BigNumber.from('44999999999999929'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            account.address,
            ethers.constants.MaxUint256);
        let balance = await poolTokenInstance1.balanceOf(account.address)

        await router.removeLiquiditySync(
            token0.address,
            token1.address,
            balance,
            balance.sub(ethers.BigNumber.from('1000000000000000')),
            true,
            account2.address,
            ethers.constants.MaxUint256);

        expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from('1529950498658957925'))
    });

    it('should remove sync liquidity ETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})

        await router.addAsyncLiquidityETH(
            token0.address,
            ethers.BigNumber.from('44999999999999929'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)});

        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();

        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);
        await ptInstance1.approve(router.address, ethers.constants.MaxUint256)
        await ptInstance0.approve(router.address, ethers.constants.MaxUint256)

        let balance = await ptInstance0.balanceOf(account.address)
        // expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2000000000000000000'))

        expect(await waffle.provider.getBalance(account2.address)).to.eq(ethers.BigNumber.from('10000000000000000000000'))
        await router.removeLiquiditySyncETH(
            token0.address,
            balance,
            ethers.BigNumber.from('910297245995400141'),
            true,
            false,
            account2.address,
            ethers.constants.MaxUint256);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1022999999999999950'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('0'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('50000000000000000'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('686331310520256337'))

        expect(await waffle.provider.getBalance(account2.address)).to.eq(ethers.BigNumber.from('10001527596822326380650'))
    });

    it('should remove liquidity', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await poolTokenInstance1.approve(router.address, ethers.constants.MaxUint256)
        await router.init(
            token0.address,
            token1.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            account.address,
            ethers.constants.MaxUint256)
        await router.addAsyncLiquidity(
            token0.address,
            token1.address,
            ethers.BigNumber.from('44999999999999929'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            account.address,
            ethers.constants.MaxUint256);
        let balance = await poolTokenInstance1.balanceOf(account.address)

        await router.removeLiquidityAsync(
            token0.address,
            token1.address,
            balance,
            ethers.BigNumber.from('1000000000000000'),
            ethers.BigNumber.from('1000000000000000'),
            true,
            account2.address,
            ethers.constants.MaxUint256);

        expect(await token1.balanceOf(account2.address)).to.eq(ethers.BigNumber.from('999999999999999020'))
        expect(await token0.balanceOf(account2.address)).to.eq(ethers.BigNumber.from('499999999999999509'))
    });
    it('should remove sync liquidity ETH', async function () {
        await token0.approve(router.address, ethers.constants.MaxUint256)
        await token1.approve(router.address, ethers.constants.MaxUint256)
        await router.initETH(
            token0.address,
            expandTo18Decimals(1),
            expandTo18Decimals(2),
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)})

        await router.addAsyncLiquidityETH(
            token0.address,
            ethers.BigNumber.from('44999999999999929'),
            ethers.BigNumber.from('22999999999999929'),
            ethers.BigNumber.from('11499999999999964'),
            ethers.BigNumber.from('20999999999999929'),
            true,
            true,
            account.address,
            ethers.constants.MaxUint256, {value: expandTo18Decimals(2)});

        let pairAddress = await factoryInstance.getPair(WETH.address, token0.address);
        let pair = await ethers.getContractFactory('ZirconPair');
        let newPair = pair.attach(pairAddress);

        let pylonAddress = await factoryPylonInstance.getPylon(WETH.address, token0.address);
        let zPylon = await ethers.getContractFactory('ZirconPylon');
        let pylon = zPylon.attach(pylonAddress);
        let poolToken1 = await ethers.getContractFactory('ZirconPoolToken');
        let poolToken2 = await ethers.getContractFactory('ZirconPoolToken');
        let poolAddress0 = await pylon.floatPoolToken();
        let poolAddress1 = await pylon.anchorPoolToken();

        let ptInstance0 = poolToken1.attach(poolAddress0);
        let ptInstance1 = poolToken2.attach(poolAddress1);

        await ptInstance1.approve(router.address, ethers.constants.MaxUint256)
        await ptInstance0.approve(router.address, ethers.constants.MaxUint256)

        let balance = await ptInstance0.balanceOf(account.address)
        // expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('2000000000000000000'))

        expect(await waffle.provider.getBalance(account2.address)).to.eq(ethers.BigNumber.from('10001527596822326380650'))
        await router.removeLiquidityAsyncETH(
            token0.address,
            balance,
            ethers.BigNumber.from('910297245995400141'),
            ethers.BigNumber.from('100'),
            true,
            false,
            account2.address,
            ethers.constants.MaxUint256);

        // Let''s check that everything was correctly minted....
        expect(await ptInstance1.balanceOf(account.address)).to.eq(ethers.BigNumber.from('1022999999999999950'))
        expect(await ptInstance0.balanceOf(account.address)).to.eq(ethers.BigNumber.from('0'))
        expect(await token0.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('50000000000000000'))
        expect(await newPair.balanceOf(pylon.address)).to.eq(ethers.BigNumber.from('652659559035182669'))

        expect(await waffle.provider.getBalance(account2.address)).to.eq(ethers.BigNumber.from('10002527596822326380148'))
    });

})
