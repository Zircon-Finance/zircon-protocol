pragma solidity >=0.5.0;

interface IZirconFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function pairCodeHash() external view returns (bytes32);

    function createPair(address tokenA, address tokenB) external returns (address pair);
    function addPylon(address pairAddress, address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address _feeTo) external;
    function setMigrator(address _migrator) external;
    function setFeeToSetter(address _feeToSetter) external;
}
