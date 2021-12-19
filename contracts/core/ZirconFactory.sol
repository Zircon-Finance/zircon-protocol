// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './ZirconPair.sol';

contract ZirconFactory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    address public migrator;

    mapping(address => mapping(address => address)) public getPair;
    address[] public  allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external  view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(ZirconPair).creationCode);
    }

    //Token A -> Anchor Token, TokenB -> Float Token
    function createPair(address tokenA, address tokenB) external  returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        require(tokenA != address(0), 'UniswapV2: ANCHOR ZERO_ADDRESS');
        require(tokenB != address(0), 'UniswapV2: FLOAT ZERO_ADDRESS');
        require(getPair[tokenA][tokenB] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ZirconPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ZirconPair(pair).initialize(tokenA, tokenB);
        getPair[tokenA][tokenB] = pair;
        //getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external  {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external  {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
