pragma solidity ^0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import './libraries/Math.sol';
import "./libraries/SafeMath.sol";
import "./ZirconERC20.sol";
import "./ZirconPair.sol";

contract ZirconPoolToken is ZirconERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint;

    address public token;
    address public pair;
    bool public isAnchor;
    address public factory;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
    uint public totalSupply;


    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
//                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }


    function mint(uint112 _reserve, uint _balance) onlyOwner nonReentrant external  returns (uint liquidity) {
        // diff anchor
        // liquidita aggiunta in float con liquidita
        // TPV * gamma
        // balance

//        (uint112 _reserve0, uint112 _reserve1, ) = ZirconPair(pair).getReserves();
//        uint balance0 = ZirconERC20(token0).balanceOf(address(this));
//        uint balance1 = ZirconERC20(token1).balanceOf(address(this));
//        uint amount0 = balance0.sub(_reserve0);
//        uint amount1 = balance1.sub(_reserve1);
//
//
//        bool feeOn = _mintFee(_reserve0, _reserve1);
//        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
//        if (_totalSupply == 0) {
//            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
//            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
//        } else {
//            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
//        }
//        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
//        _mint(to, liquidity);
//
//        _update(balance0, balance1, _reserve0, _reserve1);
//        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
//        emit Mint(msg.sender, amount0, amount1);

    }

    function redeem() onlyOwner nonReentrant external {

    }

    constructor() public {}
    // called once by the factory at time of deployment
    function initialize(address _token0, address _pair, bool _isAnchor) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token = _token0;
        pair = _pair;
        isAnchor = isAnchor;
    }
}
