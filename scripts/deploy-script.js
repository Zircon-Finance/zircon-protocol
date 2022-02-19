const { ethers } = require('hardhat');

// Deploy function
async function deploy() {
    const [account] = await ethers.getSigners();
    let deployerAddress = account.address;
    console.log(`Deploying contracts using ${deployerAddress}`);

    //Deploy WETH
    const weth = await ethers.getContractFactory('WETH');
    const wethInstance = await weth.deploy();

    console.log(`WETH deployed to : ${wethInstance.address}`);

    //Deploy Factory
    const factory = await ethers.getContractFactory('ZirconFactory');
    const factoryInstance = await factory.deploy(deployerAddress);

    console.log(`Factory deployed to : ${factoryInstance.address}`);

    //Deploy Router passing Factory Address and WETH Address
    const router = await ethers.getContractFactory('ZirconRouter');
    const routerInstance = await router.deploy(
        factoryInstance.address,
        wethInstance.address
    );
    await routerInstance.deployed();

    console.log(`Router V02 deployed to :  ${routerInstance.address}`);

    //Deploy Multicall (needed for Interface)
    const multicall = await ethers.getContractFactory('Multicall');
    const multicallInstance = await multicall.deploy();
    await multicallInstance.deployed();

    console.log(`Multicall deployed to : ${multicallInstance.address}`);

    //Deploy Tokens
    const tok1 = await ethers.getContractFactory('Token');
    const tok1Instance = await tok1.deploy('Token1', 'TOK1');

    console.log(`Token1 deployed to : ${tok1Instance.address}`);

    const tok2 = await ethers.getContractFactory('Token');
    const tok2Instance = await tok2.deploy('Token2', 'TOK2');

    console.log(`Token2 deployed to : ${tok2Instance.address}`);

    // Deploy Pylon Factory

    const pylonFactory = await ethers.getContractFactory('ZirconPylonFactory');
    let factoryPylonInstance = await pylonFactory.deploy(ethers.BigNumber.from("10000000000000000000"), ethers.BigNumber.from("8000000000000000000"),
        factoryInstance.address);
    console.log(`Pylon Factory deployed to : ${factoryPylonInstance.address}`);

    // Deploy Pylon Router
    let peripheralLibrary = await (await ethers.getContractFactory('ZirconPeripheralLibrary')).deploy();
    let pylonRouterContract = await ethers.getContractFactory('ZirconPylonRouter', {
        libraries: {
            ZirconPeripheralLibrary: peripheralLibrary.address,
        },
    });
    let pRouterInstance = await pylonRouterContract.deploy(factoryInstance.address, factoryPylonInstance.address, wethInstance.address)

    console.log(`Pylon Router deployed to : ${pRouterInstance.address}`);

}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
