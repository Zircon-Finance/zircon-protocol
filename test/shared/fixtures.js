const { ethers } = require('hardhat');
const {expandTo18Decimals} = require("./utils");

exports.coreFixtures = async function coreFixtures(address) {
    // deploy tokens
    let factory = await ethers.getContractFactory('ZirconFactory');
    let factoryInstance = await factory.deploy(address);

    let factoryPylon = await ethers.getContractFactory('ZirconPylonFactory');
    factoryPylonInstance = await factoryPylon.deploy(expandTo18Decimals(5), expandTo18Decimals(3),
        factoryInstance.address);

    // Deploy Tokens
    let tok0 = await ethers.getContractFactory('Token');
    let tk0 = await tok0.deploy('Token1', 'TOK1');
    let tok1 = await ethers.getContractFactory('Token');
    let tk1 = await tok1.deploy('Token2', 'TOK2');

    await factoryInstance.createPair(tk0.address, tk1.address);
    let lpAddress = await factoryInstance.getPair(tk0.address, tk1.address)
    let pairContract = await ethers.getContractFactory("ZirconPair");
    let pair = await pairContract.attach(lpAddress);

    const token0Address = await pair.token0();
    let token0 = tk0.address === token0Address ? tk0 : tk1
    let token1 = tk1.address === token0Address ? tk0 : tk1

    await factoryPylonInstance.addPylon(lpAddress, token0.address, token1.address);
    let pylonAddress = await factoryPylonInstance.getPylon(token0.address, token1.address)

    let zPylon = await ethers.getContractFactory('ZirconPylon')
    let poolToken1 = await ethers.getContractFactory('ZirconPoolToken')
    let poolToken2 = await ethers.getContractFactory('ZirconPoolToken')
    let pylonInstance = await zPylon.attach(pylonAddress);


    let poolAddress0 = await pylonInstance.floatPoolToken();
    let poolAddress1 = await pylonInstance.anchorPoolToken();

    let poolTokenInstance0 = poolToken1.attach(poolAddress0)
    let poolTokenInstance1 = poolToken2.attach(poolAddress1)

    return {
        factoryInstance,
        pylonInstance,
        poolTokenInstance0,
        poolTokenInstance1,
        factoryPylonInstance,
        token0,
        token1,
        pair,
    }
}