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

    // **** Constructor ****
    constructor(address _factory, address _pylonFactory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
        pylonFactory = _pylonFactory;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // *** HELPER FUNCTIONS *****
    function _getPylon(address tokenA, address tokenB) internal returns (address pylon){
        pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, UniswapV2Library.pairFor(factory, tokenA, tokenB));
    }

    // Transfers token or utility
    function _transfer(uint amountDesired, address token, address pylon) private {
        if (token == WETH) {
            IWETH(WETH).deposit{value: amountDesired}();
            assert(IWETH(WETH).transfer(pylon, amountDesired));
        }else{
            TransferHelper.safeTransferFrom(token, msg.sender, pylon, amountDesired);
        }
    }



    function _getAmounts(uint amountDesiredToken, uint amountDesiredETH, uint amountTokenMin, uint amountETHMin, bool isAnchor, address tokenA, address tokenB) internal returns (uint amountA, uint amountB){
        uint atA =  !isAnchor ? amountDesiredToken : amountDesiredETH;
        uint atB = !isAnchor ?  amountDesiredETH : amountDesiredToken;
        uint aminA = !isAnchor ? amountTokenMin : amountETHMin;
        uint aminB = !isAnchor ?  amountETHMin : amountTokenMin;
        (amountA, amountB) = _addAsyncLiquidity(tokenA, tokenB, atA, atB, aminA, aminB);
    }

    // Transfers both tokens to pylon
    function _transferAsync(address tokenA, address tokenB, uint amountA, uint amountB) internal returns (address pylon){
        pylon = _getPylon(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountB);
    }

    // Modifier to check that pylon & pair are initialized
    modifier _addLiquidityChecks(address tokenA, address tokenB) {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "ZPR: Pair Not Created");
        require(IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) != address(0), "ZPR: Pylon not created");
        // Checking if pylon is initialized
        require(ZirconPeripheralLibrary.isInitialized(pylonFactory, tokenA, tokenB, pair), "ZPR: Pylon Not Initialized");
        _;
    }
    // function called only to use the modifier to restrict the usage
    function restricted(address tokenA, address tokenB) internal _addLiquidityChecks(tokenA, tokenB){}

    // **** INIT PYLON *****
    function _initializePylon(address tokenA, address tokenB) internal virtual returns (address pair, address pylon) {
        // If Pair is not initialized
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            // Let's create it...
            pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        //Let's see if pylon is initialized
        if (IZirconPylonFactory(pylonFactory).getPylon(tokenA, tokenB) == address(0)) {
            // adds pylon
            pylon = IZirconPylonFactory(pylonFactory).addPylon(pair, tokenA, tokenB);
        }else{
            // gets the pylon address
            pylon = ZirconPeripheralLibrary.pylonFor(pylonFactory, tokenA, tokenB, pair);
        }
    }

    // Init Function with two tokens
    function init(
        address tokenA,
        address tokenB,
        uint amountDesiredA,
        uint amountDesiredB,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB){
        // Initializes the pylon
        (address pair, address pylon) = _initializePylon(tokenA, tokenB);
        // Desired amounts
        amountA = amountDesiredA;
        amountB = amountDesiredB;
        // Let's transfer to pylon
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pylon, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pylon, amountB);
        // init Pylon
        IZirconPylon(pylon).initPylon(to);
    }

    // Init Function with one token and utility token
    function initETH(
        address token,
        uint amountDesiredToken,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable  returns (uint amountA, uint amountB){

        // Initialize Pylon & Pair
        address tokenA = isAnchor ? WETH : token;
        address tokenB = isAnchor ? token : WETH;
        (, address pylon) = _initializePylon(tokenA, tokenB);
        amountA = isAnchor ? msg.value : amountDesiredToken;
        amountB = isAnchor ? amountDesiredToken : msg.value;

        // Transfering tokens to Pylon
        TransferHelper.safeTransferFrom(token, msg.sender, pylon, amountDesiredToken);
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(pylon, msg.value));

        // Calling init Pylon
        IZirconPylon(pylon).initPylon(to);
    }

    // **** ADD SYNC LIQUIDITY ****
    function addSyncLiquidity(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external returns (uint amount, uint liquidity) {
        // Checking Pylon and pair are initialized
        restricted(tokenA, tokenB);
        amount = amountDesired;
        // Getting pylon address
        address pylon = _getPylon(tokenA, tokenB);
        // Transferring tokens
        TransferHelper.safeTransferFrom(isAnchor ? tokenB : tokenA, msg.sender, pylon, amount);
        // Adding liquidity
        liquidity = IZirconPylon(pylon).mintPoolTokens(to, isAnchor);
    }

    // @isAnchor indicates if the token should be the anchor or float
    // it mints the ETH token, so the opposite of isAnchor
    // In case where we want to mint the token we should use the classic addSyncLiquidity
    // TODO: removing shouldMintAnchor change on FE
    function addSyncLiquidityETH(
        address token,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline) external payable returns (uint liquidity) {
        require(msg.value > 0, "ZPR: ZERO-VALUE");
        address tokenA = isAnchor ? WETH : token;
        address tokenB = isAnchor ? token : WETH;
        // Checking Pylon and pair are initialized
        restricted(tokenA, tokenB);
        // Getting Pylon Address
        address pylon = _getPylon(tokenA, tokenB);
        // transferring token or utility token
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(pylon, msg.value));
        // minting tokens
        liquidity = IZirconPylon(pylon).mintPoolTokens(to, !isAnchor);
    }

    // **** ASYNC-100 LIQUIDITY ******
    function addAsyncLiquidity100(
        address tokenA,
        address tokenB,
        uint amountDesired,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline) _addLiquidityChecks(tokenA, tokenB) external returns (uint liquidity){
        // Getting Pylon Address
        address pylon = _getPylon(tokenA, tokenB);
        // sending tokens to pylon
        TransferHelper.safeTransferFrom(isAnchor ? tokenB : tokenA, msg.sender, pylon, amountDesired);
        // minting async-100
        liquidity = IZirconPylon(pylon).mintAsync100(to, isAnchor);
    }

    // @isAnchor indicates if the token should be the anchor or float
    // This Function mints tokens for WETH in the contrary of @isAnchor
    function addAsyncLiquidity100ETH(
        address token,
        bool isAnchor,
        address to,
        uint deadline
    ) virtual override ensure(deadline)  external payable returns (uint liquidity){
        require(msg.value > 0, "ZPR: ZERO-VALUE");
        address tokenA = isAnchor ? WETH : token;
        address tokenB = isAnchor ? token : WETH;

        restricted(tokenA, tokenB);
        // getting pylon
        address pylon = _getPylon(tokenA, tokenB);
        // Transfering tokens
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(pylon,  msg.value));

        // Miting Async-100
        liquidity = IZirconPylon(pylon).mintAsync100(to, !isAnchor);
    }

    // **** ADD ASYNC LIQUIDITY **** //

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

        address tokenA = isAnchor ? WETH : token;
        address tokenB = isAnchor ?  token : WETH;
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

    // *** remove Sync

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
        IZirconPoolToken(shouldReceiveAnchor ? IZirconPylon(pylon).anchorPoolToken() :
            IZirconPylon(pylon).floatPoolToken()).transferFrom(msg.sender, pylon, liquidity); // send liquidity to pylon
        (amount) = IZirconPylon(pylon).burn(to, shouldReceiveAnchor);
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
        address tokenA = isAnchor ? WETH : token;
        address tokenB = isAnchor ? token : WETH;
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
