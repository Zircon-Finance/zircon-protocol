pragma solidity =0.6.6;

import "./ZirconRouter.sol";
import "./interfaces/IZirconPylonRouter.sol";

contract ZirconPylonRouter is IZirconPylonRouter {
    address public immutable override factory;
    address public immutable override pylonFactory;
    address public immutable override WETH;


    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }
    constructor(address _factory, address _pylonFactory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
        pylonFactory = _pylonFactory;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD SYNC LIQUIDITY ****
    function _addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountMin,
        bool isAnchor
    ) internal virtual returns (uint amount) {
        // checks if pylon contains pair of tokens
        if (IZirconFactory(pylonFactory).getPylon(tokenA, tokenB) == address(0)) {
            revert;
            return;
        }
        // Checking if pylon is initialized
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (!ZirconLibrary.isInizialized(tokenA, tokenB, pair)) {
            revert;
            return;
        }

        // create the pair if it doesn't exist yet
//        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
//            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
//        }

        // calculates
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        (uint reservePylonA, uint reservePylonB) = ZirconLibrary.getReserves(factory, tokenA, tokenB);

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }

    }
    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addSyncLiquidity(tokenA, tokenB, amountDesired, amountMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addSyncLiquidityETH(
        address token,
        uint amountDesired,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amountToken, uint amountETH, uint liquidity) {

    }
    function addAsyncLiquidity100(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB, uint liquidity){

    }

    function addAsyncLiquidity100ETH(
        address token,
        uint amountDesired,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amountToken, uint amountETH, uint liquidity){

    }

    function addAsyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountAMin,
        uint amountBMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB, uint liquidity){

    }
    function addAsyncLiquidityETH(
        address token,
        uint amountDesired,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amountToken, uint amountETH, uint liquidity){

    }

    function removeLiquiditySync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB){

    }
    function removeLiquiditySyncETH(
        address token,
        uint liquidity,
        uint amountMin,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountToken, uint amountETH){

    }
    function removeLiquidityAsync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB){

    }
    function removeLiquidityAsyncETH(
        address token,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountToken, uint amountETH){

    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB){

    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) virtual override ensure(deadline) external returns (uint amountToken, uint amountETH){

    }
}
