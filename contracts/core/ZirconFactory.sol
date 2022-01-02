// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import './ZirconPoolToken.sol';
import './ZirconPair.sol';
import './ZirconPylon.sol';
//import "./interfaces/IZirconPoolToken.sol";

contract ZirconFactory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    address public migrator;

    mapping(address => mapping(address => address)) public getPair;
    mapping(address => address) public getPylon;
    address[] public  allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event PylonCreated(address indexed token0, address indexed token1, address pair);
    event PoolTokenCreated(address indexed token0, address poolToken);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external  view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(ZirconPair).creationCode);
    }

    function createToken(address _token, address _pair, bool isAnchor) private returns (address poolToken) {
        // Creaating Token
        bytes memory bytecode = type(ZirconPoolToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_token));
        assembly {
            poolToken := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ZirconPoolToken(poolToken).initialize(_token, _pair, isAnchor);
        emit PoolTokenCreated(_token, poolToken);
    }

    function createPylon(address _tokenA, address _tokenB, address _pair) private returns (address pylon) {
        // Creaating Token
        bytes memory bytecode = type(ZirconPylon).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_tokenA, _tokenB, _pair));
        assembly {
            pylon := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ZirconPylon(pylon).initialize(_tokenA, _tokenB, _pair);
        emit PylonCreated(_tokenA, _tokenB, pylon);
    }


    //Token A -> Anchor Token, TokenB -> Float Token
    function createPair(address tokenA, address tokenB) external  returns (address pair) {
        require(tokenA != tokenB, 'ZirconFactory: IDENTICAL_ADDRESSES');
        require(tokenA != address(0), 'ZirconFactory: ANCHOR ZERO_ADDRESS');
        require(tokenB != address(0), 'ZirconFactory: FLOAT ZERO_ADDRESS');
        require(getPair[tokenA][tokenB] == address(0), 'ZirconFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(ZirconPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ZirconPair(pair).initialize(tokenA, tokenB);
        getPair[tokenA][tokenB] = pair;
        allPairs.push(pair);

        address poolTokenA = createToken(tokenA, pair, true);
        address poolTokenB = createToken(tokenB, pair, false);
        address pylon = createPylon(poolTokenA, poolTokenB, pair);
        getPylon[pair] = pylon;

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external  {
        require(msg.sender == feeToSetter, 'ZirconFactory: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external {
        require(msg.sender == feeToSetter, 'ZirconFactory: FORBIDDEN');
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external  {
        require(msg.sender == feeToSetter, 'ZirconFactory: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
