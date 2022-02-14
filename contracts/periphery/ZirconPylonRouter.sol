pragma solidity =0.6.6;

import "./ZirconRouter.sol";
import "./interfaces/IZirconPylonRouter.sol";
import "../core/interfaces/IZirconPair.sol";
import "../core/interfaces/IZirconPylonFactory.sol";
import "../core/interfaces/IZirconFactory.sol";
import "./libraries/ZirconPeriphericalLibrary.sol";

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
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) != address(0), "ZPR: Pylon not created");
        // Checking if pylon is initialized
        require(ZirconPeriphericalLibrary.isInitialized(factory, tokenA, tokenB, pair), "ZPR: Pylon Not Initialized");

        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        (uint reservePylonA, uint reservePylonB) = ZirconPeriphericalLibrary.getSyncReserves(factory, tokenA, tokenB, pair);
        address pylonAddress = ZirconPeriphericalLibrary.pylonFor(factory, tokenA, tokenB, pair);

        IZirconPair zp = IZirconPair(pair);
        IZirconPylonFactory pf = IZirconPylonFactory(pylonFactory);
        uint max = ZirconPeriphericalLibrary.maximumSync(
            isAnchor ? reserveA : reserveB,
            isAnchor ? reservePylonA : reservePylonB,
            pf.maximumPercentageSync(),
            isAnchor ? pf.maxAnchor() : pf.maxFloat(),
                zp.totalSupply(),
                zp.balanceOf(pylonAddress));

        require(amountDesired < max, "ZPRouter: EXCEEDS_MAX_SYNC");


    }
    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        uint amountMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amount, uint liquidity) {
        (amount) = _addSyncLiquidity(tokenA, tokenB, amountDesired, amountMin, isAnchor);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amount);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amount);
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
