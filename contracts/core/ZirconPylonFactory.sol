// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.5.16;
//import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import './ZirconPoolToken.sol';
import './ZirconPylon.sol';

contract ZirconPylonFactory {
    mapping(address => mapping(address => address)) public getPylon;
    address[] public allPylons;
    event PylonCreated(address indexed token0, address indexed token1, address pair);
    event PoolTokenCreated(address indexed token0, address poolToken);

    constructor() public {
//        feeToSetter = _feeToSetter;
    }

    function allPylonsLength() external view returns (uint) {
        return allPylons.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(ZirconPylon).creationCode);
    }

    function createTokenAddress(address _token) private returns (address poolToken) {
        // Creaating Token
        bytes memory bytecode = type(ZirconPoolToken).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_token, allPylons.length));
        assembly {
            poolToken := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
    }

    function createPylon(address _tokenA, address _tokenB, address _pair) private returns (address pylon) {
        // Creating Token
        bytes memory bytecode = type(ZirconPylon).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_tokenA, _tokenB, _pair));
        assembly {
            pylon := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ZirconPylon(pylon).initialize(_tokenA, _tokenB, _pair);
        emit PylonCreated(_tokenA, _tokenB, pylon);
    }

    function addPylon(address _pairAddress, address _tokenA, address _tokenB) external returns (address pylonAddress){
        require(getPylon[_tokenA][_tokenB] == address(0), 'ZF: PYLON_EXISTS');

        address poolTokenA = createTokenAddress(_tokenA);
        address poolTokenB = createTokenAddress(_tokenB);
        pylonAddress = createPylon(poolTokenA, poolTokenB, _pairAddress);

        ZirconPoolToken(poolTokenA).initialize(_tokenA, _pairAddress, pylonAddress, true);
        emit PoolTokenCreated(_tokenA, poolTokenA);

        ZirconPoolToken(poolTokenB).initialize(_tokenB, _pairAddress, pylonAddress, false);
        emit PoolTokenCreated(_tokenB, poolTokenB);

        getPylon[_tokenA][_tokenB] = pylonAddress;
        allPylons.push(pylonAddress);
    }
}