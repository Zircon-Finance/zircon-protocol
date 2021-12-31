const { expect } = require("chai");
const {ethers} = require("ethers");

describe("Greeter", function () {
  it("Let's create a pair", async function () {
    [account] = await ethers.getSigners();
    deployerAddress = account.address;
    console.log(`Deploying contracts using ${deployerAddress}`);

    const factory = await ethers.getContractFactory('ZirconFactory');
    const factoryInstance = await factory.deploy(deployerAddress);
    console.log(`Factory deployed to : ${factoryInstance.address}`);
    //Deploy Tokens
    const tok1 = await ethers.getContractFactory('Token');
    const tok1Instance = await tok1.deploy('Token1', 'TOK1');

    console.log(`Token1 deployed to : ${tok1Instance.address}`);

    const tok2 = await ethers.getContractFactory('Token');
    const tok2Instance = await tok2.deploy('Token2', 'TOK2');

    console.log(`Token2 deployed to : ${tok2Instance.address}`);

    await factoryInstance.createPair(tok1Instance.address, tok2Instance.address);
    const lpAddress = await factoryInstance.getPair(
        tok1Instance.address,
        tok2Instance.address
    );
  });
});
