const { expect } = require("chai");
const { ethers } = require('hardhat');

describe("Greeter", function () {
  let factory, tok1Instance, tok1, tok2, tok2Instance,
      pylonInstance, poolTokenInstance1, poolTokenInstance2;

  beforeEach(async () => {
    [account] = await ethers.getSigners();
    deployerAddress = account.address;
    console.log(`Deploying contracts using ${deployerAddress}`);

    factory = await ethers.getContractFactory('ZirconFactory');
    factoryInstance = await factory.deploy(deployerAddress);
    console.log(`Factory deployed to : ${factoryInstance.address}`);
    //Deploy Tokens
    tok1 = await ethers.getContractFactory('Token');
    tok1Instance = await tok1.deploy('Token1', 'TOK1');

    console.log(`Token1 deployed to : ${tok1Instance.address}`);

    tok2 = await ethers.getContractFactory('Token');
    tok2Instance = await tok2.deploy('Token2', 'TOK2');
    console.log(`Token2 deployed to : ${tok2Instance.address}`);

    const pylonAddress = await factoryInstance.getPylon(lpAddress);

    await factoryInstance.createPair(tok1Instance.address, tok2Instance.address);
    const lpAddress = await factoryInstance.getPair(
        tok1Instance.address,
        tok2Instance.address
    );

    let zPylon = await ethers.getContractFactory('ZirconPylon')
    let poolToken1 = await ethers.getContractFactory('ZirconPoolToken')
    let poolToken2 = await ethers.getContractFactory('ZirconPoolToken')

    pylonInstance = zPylon.attach(pylonAddress);
    let poolAddress1 = await pylonInstance.floatPoolToken();
    let poolAddress2 = await pylonInstance.anchorPoolToken();

    poolTokenInstance1 = poolToken1.attach(poolAddress1)
    poolTokenInstance2 = poolToken2.attach(poolAddress2)

    console.log("Pair Address: ", lpAddress)
    console.log("Pylon Address: ", pylonAddress)
    console.log("Pool token Address: ", poolAddress1)
    console.log("Pool token Address 2: ", poolAddress2)
  });

  it("Let's create a pair", async function () {





  });
});
