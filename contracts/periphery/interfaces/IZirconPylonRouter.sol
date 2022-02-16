pragma solidity >=0.6.2;

interface IZirconPylonRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function pylonFactory() external pure returns (address);

    function init(
        address tokenA,
        address tokenB,
        uint amountDesiredA,
        uint amountDesiredB,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function initETH(
        address token,
        uint amountDesiredToken,
        uint amountDesiredETH,
        bool isAnchor,
        address to,
        uint deadline
    ) external payable returns (uint amountA, uint amountB);

    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) external returns (uint amount, uint liquidity);

    function addSyncLiquidityETH(
        address token,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) external payable returns (uint amount, uint liquidity);
    function addAsyncLiquidity100(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) external returns (uint liquidity);

    function addAsyncLiquidity100ETH(
        address token,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) external payable returns (uint liquidity);

    function addAsyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountAMin,
        uint amountBMin,
        bool isAnchor,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addAsyncLiquidityETH(
        address token,
        uint amountDesired,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquiditySync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquiditySyncETH(
        address token,
        uint liquidity,
        uint amountMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityAsync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityAsyncETH(
        address token,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
}
