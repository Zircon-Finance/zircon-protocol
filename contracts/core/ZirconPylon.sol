pragma solidity ^0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './libraries/Math.sol';
import './ZirconPair.sol';

contract ZirconPylon {
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    address public pairAddress;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public floatPoolToken;
    address public anchorPoolToken;
    bool floatIsReserve0;

    uint virtualAnchorBalance;
    uint virtualFloatBalance;

    uint gammaMulDecimals; // Name represents the fact that this is always the numerator of a fraction with 10**18 as denominator.
    uint lastK;
    uint lastPoolTokens;
    uint percentageReserve; // Amount reserved for liquidity withdrawals/insertions
    uint ownedPoolTokens; // Used to track the pool tokens it owns but may not necessarily contain as balanceOf

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // us es single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    event PylonSync(uint112 _reserve0, uint112 _reserve1);

    // Calls dummy function with lock modifier
    modifier pairUnlocked() {
        ZirconPair(pairAddress).tryLock();
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
    }

    function getReserves()  public view returns  (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // called once by the factory at time of deployment
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _pairAddress) external {
        require(msg.sender == factory, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolToken = _floatPoolToken;
        anchorPoolToken = _anchorPoolToken;
        pairAddress = _pairAddress;
    }

//    function update() private {
//        // TODO: check current balances
//        // send balance to Pair Contract if 50-50 Liquidity
//        // remain with the other part
//        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
//    }

    //TODO: check for overflow and precision
    function getMaximum(uint _ratio, uint _token0, uint _token1) private returns (uint maxX, uint maxY)  {
        uint ty = _ratio*_token0;
        if(ty>_token1){
            maxX = _token1/_ratio;
            maxY = _token0;
        }else{
            maxY = ty;
            maxX = _token1;
        }
    }

    //TODO: Test this
    // update reserves and, on the first call per block, price accumulators
    function _update() private {
        uint112 _reserve0 = reserve0;
        uint112 _reserve1 = reserve1;
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            ZirconPair pair = ZirconPair(pairAddress);
            (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();

            uint ratio = uint(UQ112x112.encode(_pairReserve1).uqdiv(_pairReserve0));
            (uint tx, uint ty) = getMaximum(ratio, _reserve0, _reserve1);

            _safeTransfer(floatPoolToken, pairAddress, tx);
            _safeTransfer(anchorPoolToken, pairAddress, ty);
        }
        blockTimestampLast = blockTimestamp;
        emit PylonSync(reserve0, reserve1);
    }

    function mintFloatTokens() external {
        (uint112 _reserve0,,) = getReserves(); // gas savings
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);

        (uint112 _reservePair0,,) = ZirconPair(pairAddress).getReserves(); // gas savings


    }

    function mintAnchorTokens() external {

    }

    function supplyFloatLiquidity() external pairUnlocked {
        // Mints Float pool tokens to the user according to the value supplied
        // Value is derived from TWAP pool oracle
        // Follows Uniswap model — tokens are p re-sent to the contract by the router.
        sync();

        // mintFloatTokens()

        // Then sends liquidity if it has the appropriate reserves for it
        _update();
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
        // Only continues if it's called by pair itself or if the pair is unlocked
        // Which ensures it's not called within UniswapV2Callee

        if(msg.sender != pairAddress) { ZirconPair(pairAddress).tryLock(); }

        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula

        (uint112 reserve0, uint112 reserve1,) = ZirconPair(pairAddress).getReserves();
        uint price;
        uint totalPoolValue;
        uint totalPoolValuePrime;

        uint poolTokensPrime = ZirconPair(pairAddress).totalSupply();
        uint poolTokenBalance = ZirconPair(pairAddress).balanceOf(address(this));

        // What if pool token balance is 0 ?

        if(floatIsReserve0) {
            //TODO: Don't actually need oracle here, just relatively stable amount of reserve1. Or do we?
            //price = oracle.getFloatPrice(reserve0, reserve1, floatToken, anchorToken);
            //TODO: SafeMath
            totalPoolValuePrime = reserve1.mul(2).mul(poolTokenBalance/(poolTokensPrime));
            //Adjusted by the protocol's share of the entire pool.
        } else {
            // price = oracle.getFloatPrice(reserve1, reserve0, floatToken, anchorToken);
            // TODO: SafeMath
            totalPoolValuePrime = reserve0.mul(2).mul(poolTokenBalance/(poolTokensPrime));
        }

        uint kPrime = reserve0 * reserve1;

        //TODO: Fix with actual integer math
        uint feeValue = totalPoolValuePrime.mul(1 - Math.sqrt(lastK/kPrime).mul(poolTokensPrime)/lastPoolTokens);

        virtualAnchorBalance += feeValue.mul(virtualAnchorBalance)/totalPoolValuePrime;
        virtualFloatBalance += feeValue.mul(1-virtualAnchorBalance/totalPoolValuePrime);

        // Gamma is the master variable used to define withdrawals
        gammaMulDecimals = 10**18 - (virtualAnchorBalance.mul(10**18) /  totalPoolValuePrime.mul(10**18));
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
