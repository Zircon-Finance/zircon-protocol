const {ethers} = require("hardhat");

exports.expandTo18Decimals = function expandTo18Decimals(n) {return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18))}
