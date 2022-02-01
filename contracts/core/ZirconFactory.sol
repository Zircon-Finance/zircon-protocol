// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
//import './ZirconPoolToken.sol';
import './ZirconPair.sol';
//import './ZirconPylon.sol';

contract ZirconFactory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    address public migrator;

    mapping(address => mapping(address => address)) public getPair;
//    mapping(address => mapping(address => address)) public getPylon;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event PylonCreated(address indexed token0, address indexed token1, address pair);
    event PoolTokenCreated(address indexed token0, address poolToken);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(ZirconPair).creationCode);
    }

//    function createTokenAddress(address _token) private returns (address poolToken) {
//        // Creaating Token
//        bytes memory bytecode = type(ZirconPoolToken).creationCode;
//        bytes32 salt = keccak256(abi.encodePacked(_token, allPairs.length));
//        assembly {
//            poolToken := create2(0, add(bytecode, 32), mload(bytecode), salt)
//        }
//    }

//    function createPylon(address _tokenA, address _tokenB, address _pair) private returns (address pylon) {
//        // Creaating Token
//        bytes memory bytecode = type(ZirconPylon).creationCode;
//        bytes32 salt = keccak256(abi.encodePacked(_tokenA, _tokenB, _pair));
//        assembly {
//            pylon := create2(0, add(bytecode, 32), mload(bytecode), salt)
//        }
//        ZirconPylon(pylon).initialize(_tokenA, _tokenB, _pair);
//        emit PylonCreated(_tokenA, _tokenB, pylon);
//    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'ZF: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZF: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'ZF: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ZirconPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external  {
        require(msg.sender == feeToSetter, 'ZF: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external {
        require(msg.sender == feeToSetter, 'ZF: FORBIDDEN');
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external  {
        require(msg.sender == feeToSetter, 'ZF: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
