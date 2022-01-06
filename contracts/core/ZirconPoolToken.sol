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
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
    uint public totalSupply;

//    modifier onlyPylon() {
//        require(msg.sender == pylon, "Zircon Pool Token: Pylon Only");
//        _;
//    }

//    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
//        address feeTo = IUniswapV2Factory(factory).feeTo();
//        feeOn = feeTo != address(0);
//        uint _kLast = kLast; // gas savings
//        if (feeOn) {
//            if (_kLast != 0) {
//                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
//                uint rootKLast = Math.sqrt(_kLast);
//                if (rootK > rootKLast) {
//                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
//                    uint denominator = rootK.mul(5).add(rootKLast);
//                    uint liquidity = numerator / denominator;
////                    if (liquidity > 0) _mint(feeTo, liquidity);
//                }
//            }
//        } else if (_kLast != 0) {
//            kLast = 0;
//        }
//    }


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
