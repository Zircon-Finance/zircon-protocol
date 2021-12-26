pragma solidity >=0.5.0;

interface IZirconPoolToken {

    function totalSupply() external view returns (uint);
    function kLast() external view returns (uint);
    function factory() external view returns (address);
    function isAnchor() external view returns (bool);
    function token() external view returns (address);

    function _mint(uint112 _reserve, uint _balance) external;
    function redeem() external;
    function initialize(address _token0) external;
}
