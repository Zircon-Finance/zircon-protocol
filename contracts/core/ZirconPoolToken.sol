pragma solidity ^0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import './libraries/Math.sol';
import "./libraries/SafeMath.sol";
import "./ZirconERC20.sol";
import "./ZirconPair.sol";

contract ZirconPoolToken is ZirconERC20, ReentrancyGuard {
    using SafeMath for uint;

    address public token;
    address public pair;
    bool public isAnchor;
    address public factory;
    address public pylon;

    function mint(address account, uint256 amount) nonReentrant external {
        require(msg.sender == pylon, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) nonReentrant external {
        require(msg.sender == pylon, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        _burn(account, amount);
    }

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _pair, address _pylon, bool _isAnchor) external {
        require(msg.sender == factory, 'ZirconPoolToken: FORBIDDEN'); // sufficient check
        token = _token0;
        pair = _pair;
        isAnchor = isAnchor;
        pylon = _pylon;
    }
}
