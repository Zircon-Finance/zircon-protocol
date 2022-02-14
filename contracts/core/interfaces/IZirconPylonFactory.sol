pragma solidity >=0.5.16;

interface IZirconPylonFactory {
    function maxFloat() external view returns (uint);
    function maxAnchor() external view returns (uint);
    function maximumPercentageSync() external view returns (uint);
    function dynamicFeePercentage() external view returns (uint);

    function allPylons(uint p) external view returns (address);
    function getPylon(address tokenA, address tokenB) external view returns (address pair);
    function factory() external view returns (address);
    event PylonCreated(address indexed token0, address indexed token1, address pair);
    event PoolTokenCreated(address indexed token0, address poolToken);
    function allPylonsLength() external view returns (uint);
    function pairCodeHash() external pure returns (bytes32);
    // Adding Pylon
    // First Token is always the Float and the second one is the Anchor
    function addPylon(address _pairAddress, address _tokenA, address _tokenB) external returns (address pylonAddress);
}
