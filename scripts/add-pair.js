const { ethers } = require('hardhat');

// Add Pair Function
async function addPair() {
    // Deploy Pylon Router
    // let peripheralLibrary = await (await ethers.getContractFactory('ZirconPeripheralLibrary')).attach("")
    let pylonRouterContract = await ethers.getContractFactory('ZirconPylonRouter');
    pylonRouterContract.attach("0x292993357d974fA1a4aa6e37305D5F266B399f99")
    // let pRouterInstance = await pylonRouterContract.deploy(factoryInstance.address, factoryPylonInstance.address, wethInstance.address)
}

addPair()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
