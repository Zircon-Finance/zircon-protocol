pragma solidity ^0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./zircon-uniswapv2/interfaces/IUniswapV2ERC20.sol";
contract ZirconAnchor is IUniswapV2ERC20, Ownable {
    address public token;
    bool public isAnchor;

    //TODO: function mint
    //TODO: function redeem
    constructor() {}

    function mint() onlyOwner {

    }

    function redeem() onlyOwner {

    }
}
