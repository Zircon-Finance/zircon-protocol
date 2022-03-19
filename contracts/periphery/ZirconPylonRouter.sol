pragma solidity =0.6.6;

import "./ZirconRouter.sol";
import "./interfaces/IZirconPylonRouter.sol";
import "../core/interfaces/IZirconPair.sol";
import "../core/interfaces/IZirconPylonFactory.sol";
import "../core/interfaces/IZirconFactory.sol";
import "../core/interfaces/IZirconPoolToken.sol";
import "./libraries/ZirconPeripheralLibrary.sol";
import "./libraries/UniswapV2Library.sol";
//import "hardhat/console.sol";

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

    modifier _addLiquidityChecks(address tokenA, address tokenB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "ZPR: Pair Not Created");
        require(IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) != address(0), "ZPR: Pylon not created");
        // Checking if pylon is initialized
        require(ZirconPeripheralLibrary.isInitialized(pylonFactory, tokenA, tokenB, pair), "ZPR: Pylon Not Initialized");
        _;
    }

    function restricted(address tokenA, address tokenB) internal _addLiquidityChecks(tokenA, tokenB){}


    // **** INIT PYLON *****

    function _initializePylon(address tokenA, address tokenB) internal virtual returns (address pylon) {
        //consoleg("init pylon");
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            address pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
            //consoleg("init pair", pair);

        }
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        //consoleg("pair for:", pair);
        //        address e = IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB);
        //        //consoleg("pylon::", e);
        if (IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) == address(0)) {
            address pylont = IZirconPylonFactory(pylonFactory).addPylon(pair, tokenA, tokenB);
            //consoleg("pylon", pylont);
        }
        pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        //consoleg("pylon", pylon);

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


    //TODO: add min liquidity to check 50/50 transaction
    function initETH(
        address token,
        uint amountDesiredToken,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable  returns (uint amountA, uint amountB){
        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;
        address pylon = _initializePylon(tokenA, tokenB);

        amountA =  !isAnchor ? amountDesiredToken : msg.value;
        amountB = !isAnchor ?  msg.value : amountDesiredToken;

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
//    function getMax(uint reserve, uint reservePylon, address pair, address pylonAddress, bool isAnchor) internal returns (uint max) {
//        IZirconPair zp = IZirconPair(pair);
//        IZirconPylonFactory pf = IZirconPylonFactory(pylonFactory);
//        max = ZirconPeripheralLibrary.maximumSync(
//            reserve,
//            reservePylon,
//            pf.maximumPercentageSync(),
//            zp.totalSupply(),
//            zp.balanceOf(pylonAddress));
//    }


    // Only for checking modifier
    function _addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor
    ) internal virtual _addLiquidityChecks(tokenA, tokenB) returns (uint amount) {
//        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
//
//        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
//        (uint reservePairA, uint reservePairB) = ZirconPeripheralLibrary.getSyncReserves(pylonFactory, tokenA, tokenB, pair);
//        address pylonAddress = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);

//        require(amountDesired <= getMax(isAnchor ? reserveA: reserveB,
//            isAnchor ? reservePairA: reservePairB,
//            pair,
//            pylonAddress,
//            isAnchor
//        ), "ZPRouter: EXCEEDS_MAX_SYNC");

        amount = amountDesired;
    }
    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amount, uint liquidity) {
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

    // @isAnchor indicates if the token should be the anchor or float
    // This Function mints tokens for WETH in the contrary of @isAnchor
    function addSyncLiquidityETH(
        address token,
        bool isAnchor,
        bool shouldMintAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amount, uint liquidity) {
        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;

        (amount) = _addSyncLiquidity(tokenA, tokenB, msg.value, isAnchor);

        address pylon = _getPylon(tokenA, tokenB);
        _transfer(msg.value, shouldMintAnchor ? tokenB : tokenA, pylon);
        liquidity = IZirconPylon(pylon).mintPoolTokens(to, shouldMintAnchor);
        // refunds
        if(msg.value > 0) {
            if ((isAnchor && shouldMintAnchor) || (!isAnchor && !shouldMintAnchor)){
                TransferHelper.safeTransferETH(msg.sender, msg.value);
            }
        }
    }

    function addAsyncLiquidity100(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline) _addLiquidityChecks(tokenA, tokenB) external returns (uint liquidity){

        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        address pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        if (isAnchor) {
            TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountDesired);
        }else{
            TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountDesired);
        }
        liquidity = IZirconPylon(pylon).mintAsync100(to, isAnchor);


    }

    function _transfer(uint amountDesired, address token, address pylon) private {
        if (token == WETH) {
            IWETH(WETH).deposit{value: amountDesired}();
            assert(IWETH(WETH).transfer(pylon, amountDesired));
        }else{
            TransferHelper.safeTransferFrom(token, msg.sender, pylon, amountDesired);
        }
    }
    // @isAnchor indicates if the token should be the anchor or float
    // This Function mints tokens for WETH in the contrary of @isAnchor
    function addAsyncLiquidity100ETH(
        address token,
        bool isAnchor,
        bool shouldMintAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint liquidity){
        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;
        restricted(tokenA, tokenB);
        address pylon = _getPylon(tokenA, tokenB);
        _transfer(msg.value, shouldMintAnchor ? tokenB : tokenA, pylon);
        liquidity = IZirconPylon(pylon).mintAsync100(to, shouldMintAnchor);

        if(msg.value > 0) {
            if ((isAnchor && shouldMintAnchor) || (!isAnchor && !shouldMintAnchor)){
                TransferHelper.safeTransferETH(msg.sender, msg.value);
            }
        }
    }

    // **** Add Async Liquidity **** //

    function _addAsyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual _addLiquidityChecks(tokenA, tokenB) returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet

        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                //consoleg("B Optimal", amountBOptimal);
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                //consoleg("B Optimal", amountAOptimal);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }


    function _transferAsync(address tokenA, address tokenB, uint amountA, uint amountB) internal returns (address pylon){
        pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, UniswapV2Library.pairFor(factory, tokenA, tokenB));
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountB);
    }

    function addAsyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB, uint liquidity){
        (amountA, amountB) = _addAsyncLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pylon = _transferAsync(tokenA, tokenB, amountA, amountB);
        liquidity = IZirconPylon(pylon).mintAsync(to, isAnchor);
    }

    function _getAmounts(uint amountDesiredToken, uint amountDesiredETH, uint amountTokenMin, uint amountETHMin, bool isAnchor, address tokenA, address tokenB) internal returns (uint amountA, uint amountB){
        uint atA =  !isAnchor ? amountDesiredToken : amountDesiredETH;
        uint atB = !isAnchor ?  amountDesiredETH : amountDesiredToken;
        uint aminA = !isAnchor ? amountTokenMin : amountETHMin;
        uint aminB = !isAnchor ?  amountETHMin : amountTokenMin;
        (amountA, amountB) = _addAsyncLiquidity(tokenA, tokenB, atA, atB, aminA, aminB);
    }

    function _getPylon(address tokenA, address tokenB) internal returns (address pylon){
        pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, UniswapV2Library.pairFor(factory, tokenA, tokenB));
    }

    function addAsyncLiquidityETH(
        address token,
        uint amountDesiredToken,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        bool shouldReceiveAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint amountA, uint amountB, uint liquidity){

        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;
        (amountA, amountB) = _getAmounts(amountDesiredToken, msg.value, amountTokenMin, amountETHMin, isAnchor, tokenA, tokenB);
        {
            address pylon = _getPylon(tokenA, tokenB);
            TransferHelper.safeTransferFrom(isAnchor ? tokenB : tokenA, msg.sender, pylon, isAnchor ? amountB : amountA);
            IWETH(WETH).deposit{value: isAnchor ? amountA : amountB}();
            assert(IWETH(WETH).transfer(pylon, isAnchor ? amountA : amountB));
            liquidity = IZirconPylon(pylon).mintAsync(to, shouldReceiveAnchor);
        }
        // refund dust eth, if any
        if (msg.value > (isAnchor ? amountA : amountB)) TransferHelper.safeTransferETH(msg.sender, msg.value - (isAnchor ? amountA : amountB));
    }

    function removeLiquiditySync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountMin,
        bool shouldReceiveAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  public returns (uint amount){
        address pylon = _getPylon(tokenA, tokenB);
        IZirconPoolToken(shouldReceiveAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken()).transferFrom(msg.sender, pylon, liquidity); // send liquidity to pair
        (amount) = IZirconPylon(pylon).burn(to, shouldReceiveAnchor);
        //consoleg("withdrawing amount", amount);
        require(amount >= amountMin, 'UniswapV2Router: INSUFFICIENT_AMOUNT');
    }

    function removeLiquiditySyncETH(
        address token,
        uint liquidity,
        uint amountMin,
        bool isAnchor,
        bool shouldRemoveAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amount){
        address tokenA = !isAnchor ? token : WETH;
        address tokenB = !isAnchor ?  WETH : token;
        (amount) = removeLiquiditySync(
            tokenA,
            tokenB,
            liquidity,
            amountMin,
            shouldRemoveAnchor,
            (isAnchor && shouldRemoveAnchor) || (!shouldRemoveAnchor && !isAnchor) ? to : address(this),
            deadline
        );
        if ((isAnchor && !shouldRemoveAnchor) || (shouldRemoveAnchor && !isAnchor)) {
            IWETH(WETH).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        }
    }
    function removeLiquidityAsync(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  public returns (uint amountA, uint amountB){
        address pylon = _getPylon(tokenA, tokenB);
        IZirconPoolToken(isAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken()).transferFrom(msg.sender, pylon, liquidity); // send liquidity to pair
        (amountA, amountB) = IZirconPylon(pylon).burnAsync(to, isAnchor);
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');

    }
    function removeLiquidityAsyncETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        bool isAnchor,
        bool shouldBurnAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amountToken, uint amountETH){
        {
            (uint amountA, uint amountB) = removeLiquidityAsync(
                !isAnchor ? token : WETH,
                !isAnchor ? WETH : token,
                liquidity,
                amountTokenMin,
                amountETHMin,
                shouldBurnAnchor,
                address(this),
                deadline
            );
            amountToken = !isAnchor ? amountA : amountB;
            amountETH = !isAnchor ?  amountB : amountA;
        }
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    //    function removeLiquiditySyncWithPermit(
    //        address tokenA,
    //        address tokenB,
    //        uint liquidity,
    //        uint amountMin,
    //        bool isAnchor,
    //        address to,
    //        uint deadline,
    //        bool approveMax, uint8 v, bytes32 r, bytes32 s
    //    ) virtual override ensure(deadline)  external returns (uint amount){
    //        address pylon = _getPylon(tokenA, tokenB);
    //        uint value = approveMax ? uint(-1) : liquidity;
    //        IZirconPoolToken(isAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken()).permit(msg.sender, address(this), value, deadline, v, r, s);
    //        (amount) = removeLiquiditySync(tokenA, tokenB, liquidity, amountMin, isAnchor, to, deadline);
    //    }
    //
    //    function removeLiquidityETHWithPermit(
    //        address token,
    //        uint liquidity,
    //        uint amountMin,
    //        bool isAnchor,
    //        bool shouldRemoveAnchor,
    //        address to,
    //        uint deadline,
    //        bool approveMax, uint8 v, bytes32 r, bytes32 s
    //    ) virtual override ensure(deadline) external returns (uint amount){
    //        address pylon = UniswapV2Library.pairFor(factory, token, WETH);
    //        uint value = approveMax ? uint(-1) : liquidity;
    //        IZirconPoolToken(shouldRemoveAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken())
    //        .permit(msg.sender, address(this), value, deadline, v, r, s);
    //        (amount) = removeLiquiditySyncETH(
    //            token,
    //            liquidity,
    //            amountMin,
    //            isAnchor,
    //            shouldRemoveAnchor,
    //            to,
    //            deadline);
    //    }
    //
    //    function removeLiquidityAsyncWithPermit(
    //        address token,
    //        uint liquidity,
    //        uint amountTokenMin,
    //        uint amountETHMin,
    //        bool isAnchor,
    //        bool shouldBurnAnchor,
    //        address to,
    //        uint deadline,
    //        bool approveMax, uint8 v, bytes32 r, bytes32 s
    //    ) virtual override ensure(deadline)  external returns (uint amountA, uint amountB){
    //        address tokenA = !isAnchor ? token : WETH;
    //        address tokenB = !isAnchor ?  WETH : token;
    //
    //        address pylon = _getPylon(tokenA, tokenB);
    //        uint value = approveMax ? uint(-1) : liquidity;
    //        IZirconPoolToken(shouldRemoveAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken())
    //        .permit(msg.sender, address(this), value, deadline, v, r, s);
    //        (amountA, amountB) = removeLiquidityAsyncETH(token, liquidity, amountAMin, amountBMin, isAnchor, to, deadline);
    //
    //    }

    //    function removeLiquidityAsyncETHWithPermit(
    //        address token,
    //        uint liquidity,
    //        uint amountTokenMin,
    //        uint amountETHMin,
    //    bool isAnchor,
    //        bool shouldBurnAnchor,
    //        address to,
    //        uint deadline,
    //        bool approveMax, uint8 v, bytes32 r, bytes32 s
    //    ) virtual override ensure(deadline) external returns (uint amountA, uint amountB){
    //        address pylon = _getPylon(tokenA, tokenB);
    //        uint value = approveMax ? uint(-1) : liquidity;
    //        IZirconPoolToken(shouldRemoveAnchor ? IZirconPylon(pylon).anchorPoolToken() : IZirconPylon(pylon).floatPoolToken())
    //        .permit(msg.sender, address(this), value, deadline, v, r, s);
    //        (amountA, amountB) = removeLiquidityAsync(token, liquidity, amountTokenMin, amountETHMin, isAnchor, shouldBurnAnchor, to, deadline);
    //
    //    }
}
