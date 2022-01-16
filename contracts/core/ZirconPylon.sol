pragma solidity ^0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './libraries/Math.sol';
import './interfaces/IZirconPair.sol';
import './interfaces/IZirconPoolToken.sol';
import "./libraries/SafeMath.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "./ZirconPylonFactory.sol";
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

contract ZirconPylon {
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    address public pairAddress;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    uint public constant MINIMUM_LIQUIDITY = 10**3;

    address public factory;
    address public floatPoolToken;
    address public anchorPoolToken;
    address public token0;
    address public token1;
    uint public maxFloatSync;
    uint public maxAnchorSync;

    uint virtualAnchorBalance;
    uint virtualFloatBalance;
    uint maximumPercentageSync;

    uint gammaMulDecimals; // Name represents the fact that this is always the numerator of a fraction with 10**18 as denominator.
    uint lastK;
    uint lastPoolTokens;
    uint percentageReserve; // Amount reserved for liquidity withdrawals/insertions
    uint ownedPoolTokens; // Used to track the pool tokens it owns but may not necessarily contain as balanceOf

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves (always anchor)
    uint112 private reserve1;           // us es single storage slot, accessible via getReserves (always float)
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event PylonSync(uint112 _reserve0, uint112 _reserve1);
    event MintPT(uint112 _reserve0, uint112 _reserve1);
    event PylonUpdate(uint tx, uint ty, uint tp);

    // Calls dummy function with lock modifier
    modifier pairUnlocked() {
        IZirconPair(pairAddress).tryLock();
        _;
    }

    modifier blockRecursion() {
        // TODO: Should do some kind of block height check to ensure this user hasn't
        // already called any of these functions
        _;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Zircon Pylon: TRANSFER_FAILED');
    }


    constructor() public {
        factory = msg.sender;
        maximumPercentageSync = 10;
    }

    function getReserves()  public view returns  (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // called once by the factory at time of deployment
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _token0, address _token1, address _pairAddress) external {
        require(msg.sender == factory, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolToken = _floatPoolToken;
        anchorPoolToken = _anchorPoolToken;
        pairAddress = _pairAddress;
        token0 = _token0;
        token1 = _token1;
        maxFloatSync = ZirconPylonFactory(factory).maxFloat();
        maxAnchorSync = ZirconPylonFactory(factory).maxAnchor();
    }


    function _getMaximum(uint _ratio, uint _token0, uint _token1) private returns (uint maxX, uint maxY)  {
        uint ty = _ratio*_token0;
        if(ty>_token1){
            maxX = _token1/_ratio;
            maxY = _token0;
        }else{
            maxY = ty;
            maxX = _token1;
        }
    }


    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // overflow is desired
        IZirconPoolToken pt = IZirconPoolToken(floatPoolToken);
        IZirconPoolToken at = IZirconPoolToken(anchorPoolToken);
        IZirconPair pair = IZirconPair(pairAddress);
        (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();

        if (timeElapsed > 0 && balance0 != 0 && balance1 != 0) {
            uint ratio = _pairReserve1/_pairReserve0;
            (uint tx, uint ty) = _getMaximum(ratio, balance0, balance1);
            emit PylonUpdate(ratio, ty, tx);

            _safeTransfer(pt.token(), pairAddress, tx);
            _safeTransfer(at.token(), pairAddress, ty);
            pair.mint(address(this));

            reserve0 = uint112(balance0.sub(tx));
            reserve1 = uint112(balance1.sub(ty));
        }

        blockTimestampLast = blockTimestamp;
    }

    // Minting

    function _mintFee(uint amount, address poolToken) private returns (bool feeOn){
        address feeTo = ZirconPylonFactory(factory).feeToo();
        IZirconPoolToken pt = IZirconPoolToken(poolToken);
        feeOn = feeTo != address(0);
        if (feeOn) {
            pt.mint(feeTo, amount);
        }
    }

    function _mintPoolToken(uint _balance, uint112 _reserve, uint112 _pairReserve, address _poolTokenAddress, address _to) private returns (uint liquidity) {
        address feeTo = ZirconPylonFactory(factory).feeToo();
        IZirconPoolToken pt = IZirconPoolToken(_poolTokenAddress);
        uint amountIn = _balance.sub(_reserve);
        uint fee = feeTo != address(0) ? amountIn/1000 : 0; //TODO make dynamic
        uint toTransfer = amountIn-fee;
        require(toTransfer > 0, "ZP: Not Enough Liquidity");
        uint maxSync = (_pairReserve == 0 || _reserve > _pairReserve) ? maxFloatSync.mul(100) :
        _pairReserve.mul(maximumPercentageSync).sub(_reserve.mul(100));
        liquidity = (maxSync > toTransfer.mul(100)) ? maxSync : toTransfer;

        uint totalSupply = pt.totalSupply();

        pt.mint(_to, liquidity);
        _mintFee(fee, _poolTokenAddress);
        emit MintPT(reserve0, reserve1);

    }

    function mintPoolTokens(address to, bool isAnchor) external returns (uint liquidity) {
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (uint112 _reservePair0, uint112 _reservePair1,) = IZirconPair(pairAddress).getReserves();

        if (isAnchor) {
            liquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, to);
        }else{
            liquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, to);
        }

        _update(balance0, balance1, reserve0, reserve1);
    }
    // TODO: update value using oracle
    function mintAsync(address to, bool shouldMintAnchor) external lock returns (uint liquidity){
        IZirconPair pair = IZirconPair(pairAddress);
        IZirconPoolToken pt = IZirconPoolToken(floatPoolToken);
        IZirconPoolToken at = IZirconPoolToken(anchorPoolToken);

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings

        uint toTransfer0;
        uint toTransfer1;
        uint fee0;
        uint fee1;
        uint balance0;
        uint balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            address feeTo = ZirconPylonFactory(factory).feeToo();
            uint balance0 = IERC20Uniswap(_token0).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(_token1).balanceOf(address(this));
            uint amountIn0 = balance0.sub(_reserve0);
            uint amountIn1 = balance1.sub(_reserve1);

            fee0 = feeTo == address(0) ? 0 : amountIn0/1000;
            fee1 = feeTo == address(0) ? 0 : amountIn0/1000;
            toTransfer0 = amountIn0.sub(fee0);
            toTransfer1 = amountIn1.sub(fee1);
        }

        require(toTransfer0 > 0 && toTransfer1 > 0, "ZirconPylon: Not Enough Liquidity");
        uint _totalSupply = pair.totalSupply();

        if (shouldMintAnchor) {
            {
                address _to = to;
                (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();
                uint ratio = _pairReserve0/_pairReserve1 ;
                uint amount1InAnchor = ratio.mul(toTransfer1);
                at.mint(_to, amount1InAnchor);
                emit MintPT(reserve0, reserve1);
            }
        }else{
            {
                address _to = to;
                (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();
                uint ratio = _pairReserve1/_pairReserve0;
                uint amount0InFloat = ratio.mul(toTransfer0);
                pt.mint(_to, amount0InFloat);
                emit MintPT(reserve1, reserve0);
            }
        }

        _mintFee(fee1, anchorPoolToken);
        _mintFee(fee0, floatPoolToken);
        _update(balance0, balance1, reserve0, reserve1);
    }

    function supplyFloatLiquidity() external pairUnlocked {
        // Mints Float pool tokens to the user according to the value supplied
        // Value is derived from TWAP pool oracle
        // Follows Uniswap model — tokens are pre-sent to the contract by the router.
        sync();

        // mintFloatTokens()

        // Then sends liquidity if it has the appropriate reserves for it
        //        _update();
    }

    function removeFloatLiquidity() external pairUnlocked {
        sync();

        _extractFloatLiquidity();
    }

    function supplyAnchorLiquidity() external pairUnlocked {
        sync();

        _sendLiquidity();
    }

    function removeAnchorLiquidity() external pairUnlocked {
        sync();

        _extractAnchorLiquidity();
    }

    function sync() public {
        // TODO: Only continues if it's called by pair itself or if the pair is unlocked
        // Which ensures it's not called within UniswapV2Callee

        if(msg.sender != pairAddress) { IZirconPair(pairAddress).tryLock(); }

        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula

        (uint112 reserve0, uint112 reserve1,) = IZirconPair(pairAddress).getReserves();
        uint price;
        uint totalPoolValue;
        uint totalPoolValuePrime;

        uint poolTokensPrime = IZirconPair(pairAddress).totalSupply(); // total supply could be 0 at the beginning
        uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this)); // What if pool token balance is 0 ?

        // TODO: Don't actually need oracle here, just relatively stable amount of reserve1. Or do we?
        // Adjusted by the protocol's share of the entire pool.
        // price = oracle.getFloatPrice(reserve1, reserve0, floatToken, anchorToken);
        // TODO: SafeMath
        totalPoolValuePrime = reserve0.mul(2).mul(poolTokenBalance/(poolTokensPrime));

        uint kPrime = reserve0 * reserve1;

        // TODO: Fix with actual integer math
        // only if lastK > kPrime ?
        uint feeValue = totalPoolValuePrime.mul(1 - Math.sqrt(lastK/kPrime).mul(poolTokensPrime)/lastPoolTokens);

        virtualAnchorBalance += feeValue.mul(virtualAnchorBalance)/totalPoolValuePrime;
        // TODO: Formula
        virtualFloatBalance += feeValue.mul(1-virtualAnchorBalance/totalPoolValuePrime);

        // Gamma is the master variable used to define withdrawals
        gammaMulDecimals = 1 - (virtualAnchorBalance /  totalPoolValuePrime);
        // 1 - ATV/TPV but multiplied by 10**18 due to integer math shit
    }

    // Called at the end of supply functions to supply any available 50-50 liquidity to underlying pool
    function _sendLiquidity() private { }

    // Called by remove functions if a withdrawal requires underlying liquidity extraction
    function _extractFloatLiquidity() private {
        // Sends tokens from self if it has them
        // Otherwise directs pool to send them to user
        // TODO: maybe we can do some kind of self-flash swap to make it swap with less slippage (before liquidity is removed)?
        // TODO: Also to avoid needless ERC-20 transfers
        // TODO: Or just literally send tokens from the pool
    }

    function _extractAnchorLiquidity() private {
        //redeems owned pool tokens, swaps them with the pool to deliver only anchor asset
    }
}
