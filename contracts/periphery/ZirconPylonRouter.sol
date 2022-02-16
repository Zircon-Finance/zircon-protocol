pragma solidity =0.6.6;

import "./ZirconRouter.sol";
import "./interfaces/IZirconPylonRouter.sol";
import "../core/interfaces/IZirconPair.sol";
import "../core/interfaces/IZirconPylonFactory.sol";
import "../core/interfaces/IZirconFactory.sol";
import "./libraries/ZirconPeripheralLibrary.sol";
import "./libraries/UniswapV2Library.sol";
import "hardhat/console.sol";

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

    // **** INIT PYLON *****

    function _initializePylon(address tokenA, address tokenB) internal virtual returns (address pylon) {
        console.log("init pylon");
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            address pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
            console.log("init pair", pair);

        }
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        console.log("pair for:", pair);
//        address e = IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB);
//        console.log("pylon::", e);
        if (IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) == address(0)) {
            address pylont = IZirconPylonFactory(pylonFactory).addPylon(pair, tokenA, tokenB);
            console.log("pylon", pylont);
        }
        pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        console.log("pylon", pylon);

    }

    function init(
        address tokenA,
        address tokenB,
        uint amountDesiredA,
        uint amountDesiredB,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB){
        address pylon = _initializePylon(tokenA, tokenB);
        amountA = amountDesiredA;
        amountB = amountDesiredB;
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountB);
        IZirconPylon(pylon).initPylon(to);
    }

    function initETH(
        address token,
        uint amountDesiredToken,
        uint amountDesiredETH,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable  returns (uint amountA, uint amountB){
        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;
        address pylon = _initializePylon(tokenA, tokenB);

        amountA =  !isAnchor ? amountDesiredToken : amountDesiredETH;
        amountB = !isAnchor ?  amountDesiredETH : amountDesiredToken;

        if (isAnchor) {
            TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountB);

            IWETH(WETH).deposit{value: amountA}();
            assert(IWETH(WETH).transfer(pylon, amountA));
            // refunds
            if (msg.value > amountA) TransferHelper.safeTransferETH(msg.sender, msg.value - amountA);
        }else{
            TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountA);
            IWETH(WETH).deposit{value: amountB}();
            assert(IWETH(WETH).transfer(pylon, amountB));
            // refunds
            if (msg.value > amountB) TransferHelper.safeTransferETH(msg.sender, msg.value - amountB);
        }
        IZirconPylon(pylon).initPylon(to);
    }

    // **** ADD SYNC LIQUIDITY ****
    function _addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor
    ) internal virtual returns (uint amount) {
        // checks if pylon contains pair of tokens
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);

        require(pair != address(0), "ZPR: Pair Not Created");
        require(IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) != address(0), "ZPR: Pylon not created");
        // Checking if pylon is initialized
        require(ZirconPeripheralLibrary.isInitialized(pylonFactory, tokenA, tokenB, pair), "ZPR: Pylon Not Initialized");

        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        (uint reservePylonA, uint reservePylonB) = ZirconPeripheralLibrary.getSyncReserves(pylonFactory, tokenA, tokenB, pair);
        address pylonAddress = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);

        IZirconPair zp = IZirconPair(pair);
        IZirconPylonFactory pf = IZirconPylonFactory(pylonFactory);
        uint max = ZirconPeripheralLibrary.maximumSync(
            isAnchor ? reserveA : reserveB,
            isAnchor ? reservePylonA : reservePylonB,
            pf.maximumPercentageSync(),
            isAnchor ? pf.maxAnchor() : pf.maxFloat(),
            zp.totalSupply(),
            zp.balanceOf(pylonAddress));
        console.log(max);
        require(amountDesired <= max, "ZPRouter: EXCEEDS_MAX_SYNC");

        amount = amountDesired;
    }
    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline) external returns (uint amount, uint liquidity) {
        (amount) = _addSyncLiquidity(tokenA, tokenB, amountDesired, isAnchor);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        address pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        if (isAnchor) {
            TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amount);
        }else{
            TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amount);
        }
        liquidity = IZirconPylon(pylon).mintPoolTokens(to, isAnchor);
    }

    function addSyncLiquidityETH(
        address token,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amount, uint liquidity) {
        address tokenA = isAnchor ? token : WETH;
        address tokenB = isAnchor ?  WETH : token;

        (amount) = _addSyncLiquidity(tokenA, tokenB, amountDesired, isAnchor);

        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        address pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        IWETH(WETH).deposit{value: amount}();
        assert(IWETH(WETH).transfer(pylon, amount));
        // refunds
        if (msg.value > amount) TransferHelper.safeTransferETH(msg.sender, msg.value - amount);

        liquidity = IZirconPylon(pylon).mintPoolTokens(to, isAnchor);
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
