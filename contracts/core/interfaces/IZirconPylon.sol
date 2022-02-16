pragma solidity >=0.5.16;
interface IZirconPylon {

    function initialized() external view returns (uint);
    function anchorPoolToken() external view returns (address);
    function floatPoolToken() external view returns (address);
    function getSyncReserves() external view returns  (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    // Called once by the factory at time of deployment
    // @_floatPoolToken -> Contains Address Of Float PT
    // @_anchorPoolToken -> Contains Address Of Anchor PT
    // @token0 -> Float token
    // @token1 -> Anchor token
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _token0, address _token1, address _pairAddress, address _pairFactory) external;
    // On init pylon we have to handle two cases
    // The first case is when we initialize the pair through the pylon
    // And the second one is when initialize the pylon with a pair already existing
    function initPylon(address _to) external;
    // External Function called to mint pool Token
    // Liquidity have to be sent before
    function mintPoolTokens(address to, bool isAnchor) external returns (uint liquidity);
    function mintAsync100(address to, bool isAnchor) external returns (uint liquidity);
    function mintAsync(address to, bool shouldMintAnchor) external returns (uint liquidity);
    // Burn Async send both tokens 50-50
    // Liquidity has to be sent before
    function burnAsync(address _to, bool _isAnchor) external;
    // Burn send liquidity back to user burning Pool tokens
    // The function first uses the reserves of the Pylon
    // If not enough reserves it burns The Pool Tokens of the pylon
    function burn(address _to, bool _isAnchor) external returns (uint amount);
}
