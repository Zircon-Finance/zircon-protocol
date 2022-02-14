pragma solidity ^0.5.16;

contract IZirconPylonFactory {
    function maxFloat() external view returns (uint);
    function maxAnchor() external view returns (uint);
    function allPylons(uint) external view returns (address);
    function getPylon(address tokenA, address tokenB) external view returns (address pair);
    function factory() external view returns (address);

    event PylonCreated(address indexed token0, address indexed token1, address pair);
    event PoolTokenCreated(address indexed token0, address poolToken);

    function allPylonsLength() external view returns (uint);

    function pairCodeHash() external pure returns (bytes32);
    function createTokenAddress(address _token) private returns (address poolToken);

    function createPylon(address _fptA, address _fptB, address _tokenA, address _tokenB, address _pair) private returns (address pylon);


    // Adding Pylon
    // First Token is always the Float and the second one is the Anchor
    function addPylon(address _pairAddress, address _tokenA, address _tokenB) external returns (address pylonAddress);
}
