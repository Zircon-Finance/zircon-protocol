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
import "hardhat/console.sol";


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

    uint public virtualAnchorBalance; // TODO: make private
    uint public virtualFloatBalance; // TODO: make private
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
    uint private initialized = 0;
    uint private testMultiplier = 1e18;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'ZP: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier isInitialized() {
        require(initialized == 1, 'ZP: NOT INITIALIZED');
        _;
    }

    // TODO: emit correct events
    event PylonSync(uint112 _reserve0, uint112 _reserve1);
    event MintPT(uint112 _reserve0, uint112 _reserve1);
    event PylonUpdate(uint _reserve0, uint _reserve1);

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

    function initPylon(address _to) external lock{
        require(initialized == 0, "Already Initialized");
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (uint112 _reservePair0, uint112 _reservePair1,) = IZirconPair(pairAddress).getReserves();
        console.log("<<<Pylon:_mintPoolToken::::::::start:anchor");
        uint anchorLiquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, _to);
        console.log("<<<Pylon:_mintPoolToken::::::::start:float");
        uint floatLiquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, _to);
        virtualAnchorBalance = anchorLiquidity;
        virtualFloatBalance = floatLiquidity;
        _update(reserve0, reserve1);
        initialized = 1;
    }


    function _getMaximum(uint _pR0, uint _pR1, uint _b0, uint _b1) private returns (uint maxX, uint maxY)  {
        uint tx = _pR0.mul(_b1)/_pR1;
        if (tx > _b0) {
            maxX = _b0;
            maxY = _b0.mul(_pR1)/_pR0;
        } else {
            maxX = tx;
            maxY = _b1;
        }
    }

    function updateReservesRemovingExcess(uint balance0, uint balance1, uint112 max0, uint112 max1) private {
        uint112 newReserve0 = uint112(balance0);
        uint112 newReserve1 = uint112(balance1);
        console.log("<<<Pylon:newReserve::::::::", newReserve0/testMultiplier, newReserve1/testMultiplier);

        if (max0 < newReserve0) {
            uint112 excessReserves = uint112(newReserve0.sub(max0));
            _safeTransfer(token0, pairAddress, excessReserves);
            reserve0 = max0;
            console.log("<<<Pylon:excessReserves0::::::::", excessReserves/testMultiplier);
        } else {
            reserve0 = newReserve0;
        }
        if (max1 < newReserve1) {
            uint112 excessReserves = uint112(newReserve1.sub(max1));
            _safeTransfer(token1, pairAddress, excessReserves);
            reserve1 = max1;
            console.log("<<<Pylon:excessReserves1::::::::", excessReserves/testMultiplier);
        }else{
            reserve1 = newReserve1;
        }
        console.log("<<<Pylon:new res::::::::", reserve0/testMultiplier, reserve1/testMultiplier);
        emit PylonUpdate(reserve0, reserve1);
    }


    // Update reserves and, on the first call per block, price accumulator
    // Any excess of balance is going to be donated to the pair
    // So... here we get the maximum of both tokens and we mint Pool Tokens
    //TODO: think a way to do only one transfer by token
    function _update(uint112 _reserve0, uint112 _reserve1) private {
        console.log("<<<Pylon:_update::::::::start");

        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        IZirconPoolToken pt = IZirconPoolToken(floatPoolToken);
        IZirconPoolToken at = IZirconPoolToken(anchorPoolToken);
        IZirconPair pair = IZirconPair(pairAddress);
        (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();

        // Calculating max
        uint112 max0 = uint112(_pairReserve0/(maximumPercentageSync));
        uint112 max1 = uint112(_pairReserve1/(maximumPercentageSync));

        console.log("<<<Pylon:balances::::::::", balance0/testMultiplier, balance1/testMultiplier);
        console.log("<<<Pylon:pairReserves::::::::", _pairReserve0/testMultiplier, _pairReserve1/testMultiplier);

        // Pylon Update Minting
        //TODO: check if it is necessary a timeElapsed check
        //TODO: if _pair reserves are 0 we have to send all liquidity to initialize the pair
        console.log("<<<Pylon:values::maxes::::::::", max0/testMultiplier, max1/testMultiplier);
        if (balance0 > max0/2 && balance1 > max1/2) {
            console.log("<<<Pylon:values::getMax::::::::", balance0/10**18, balance1/10**18);
            (uint tx, uint ty) = _getMaximum(_pairReserve0, _pairReserve1, balance0.sub(max0/2), balance1.sub(max1/2));
            console.log("<<<Pylon:_getMaximum::::::::", tx/testMultiplier, ty/testMultiplier);
            if(tx != 0) _safeTransfer(token0, pairAddress, tx);
            if(ty != 0) _safeTransfer(token1, pairAddress, ty);
            pair.mint(address(this));
            balance0 -= tx;
            balance1 -= ty;
        }
        // 2022

        // Pylon Update Transfers exceeding Token
        updateReservesRemovingExcess(balance0, balance1, max0, max1);

        // Updating Variables
        _updateVariables(_pairReserve0, _pairReserve1);
        console.log("<<<Pylon:update::::::::end\n\n");

    }

    function _updateVariables(uint _pairReserve0, uint _pairReserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        blockTimestampLast = blockTimestamp;
        lastPoolTokens = IZirconPair(pairAddress).totalSupply();
        lastK = uint(_pairReserve0).mul(_pairReserve1);
        console.log("<<<Pylon:_updateVariables::::::::", _pairReserve0, _pairReserve1);

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
        console.log("<<<Pylon:_mintPoolToken::::::::start");
        address feeTo = ZirconPylonFactory(factory).feeToo();
        IZirconPoolToken pt = IZirconPoolToken(_poolTokenAddress);
        uint amountIn = _balance.sub(_reserve);
        console.log("<<<Pylon:::::::amountIn>>>> ", amountIn/testMultiplier);
        uint fee = feeTo != address(0) ? amountIn/1000 : 0;
        console.log("<<<Pylon:::::::fee>>>> ", fee);
        uint toTransfer = amountIn-fee;
        console.log("<<<Pylon:::::::toTransfer>>>> ", toTransfer/testMultiplier);
        require(toTransfer > 0, "ZP: Not Enough Liquidity");
        console.log("<<<Pylon:::::::PairReserve>>>> ", _pairReserve/testMultiplier);

        uint maxSync = (_pairReserve == 0 || _reserve > _pairReserve) ? maxFloatSync :
        (_pairReserve.mul(maximumPercentageSync)/100).sub(_reserve);
        console.log("<<<Pylon:::::::maxSync>>>> ", maxSync/testMultiplier);
        liquidity = (maxSync < toTransfer) ? maxSync : toTransfer;
        console.log("<<<Pylon:::::::liquidity>>>> ", liquidity/testMultiplier);
        pt.mint(_to, liquidity);
        if (fee != 0) _mintFee(fee, _poolTokenAddress);
        emit MintPT(reserve0, reserve1);
        console.log("<<<Pylon:_mintPoolToken::::::::end \n\n");
    }

    function mintPoolTokens(address to, bool isAnchor) isInitialized external returns (uint liquidity) {
        sync();
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (uint112 _reservePair0, uint112 _reservePair1,) = IZirconPair(pairAddress).getReserves();

        if (isAnchor) {
            console.log("<<<Pylon:_mintPoolToken::::::::anchor");
            liquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, to);
        }else{
            console.log("<<<Pylon:_mintPoolToken::::::::float");
            liquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, to);
        }
        _update(reserve0, reserve1);
    }

    //TODO: Clean up this function
    //TODO: Transfer first then calculate on basis of pool token share how many share we should give to the user
    function mintAsync(address to, bool shouldMintAnchor) external lock isInitialized returns (uint liquidity){
        console.log("<<<Pylon:mintAsync::::::::start");
        sync();
        IZirconPoolToken pt = IZirconPoolToken(shouldMintAnchor ? anchorPoolToken : floatPoolToken);
        IZirconPair pair = IZirconPair(pairAddress);
        (uint112 _pairReserve0, uint112 _pairReserve1, ) = pair.getReserves();

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint _totalSupply = pair.totalSupply();

        uint toTransfer0;
        uint toTransfer1;
        uint fee0;
        uint fee1;
        {
            address _token0 = token0;
            address _token1 = token1;
            IZirconPair _pair = pair;
            address feeTo = ZirconPylonFactory(factory).feeToo();
            uint balance0 = IERC20Uniswap(_token0).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(_token1).balanceOf(address(this));
            console.log("<<<Pylon:r::::::::", balance0/testMultiplier, reserve0/testMultiplier);
            console.log("<<<Pylon:m::::::::", balance1/testMultiplier, reserve1/testMultiplier);
            uint amountIn0 = balance0.sub(_reserve0);
            uint amountIn1 = balance1.sub(_reserve1);
            console.log("<<<Pylon:first::::::::", amountIn0, amountIn1);

            fee0 = feeTo == address(0) ? 0 : amountIn0/1000;
            fee1 = feeTo == address(0) ? 0 : amountIn0/1000;
            console.log("<<<Pylon:fee::::::::", fee0, fee1);

            toTransfer0 = amountIn0.sub(fee0);
            toTransfer1 = amountIn1.sub(fee1);
            console.log("<<<Pylon:toTransfer::::::::", toTransfer0/testMultiplier, toTransfer1/testMultiplier);
            require(toTransfer0 > 0 && toTransfer1 > 0, "ZirconPylon: Not Enough Liquidity");
            _safeTransfer(token0, pairAddress, toTransfer0);
            _safeTransfer(token1, pairAddress, toTransfer1);
            _pair.mint(address(this));
        }
//        uint deltaSupply = pair.totalSupply().sub(_totalSupply);
        // TODO: maybe another formula is faster
        // TODO: check maximum to mint
        if (shouldMintAnchor) {
            liquidity = (_pairReserve1.mul(toTransfer0)/_pairReserve0).add(toTransfer1);
        }else{
            liquidity = (toTransfer1.mul(_pairReserve0)/_pairReserve1).add(toTransfer0);
        }
        pt.mint(to, liquidity);
        emit MintPT(reserve1, reserve0);
        console.log("<<<Pylon:liquidity::::::::", liquidity/testMultiplier);

        if (fee0 != 0) _mintFee(fee1, anchorPoolToken);
        if (fee1 != 0) _mintFee(fee0, floatPoolToken);
        console.log("<<<Pylon:mintAsync:::::::: \n\n");

        _updateVariables(_pairReserve0, _pairReserve1);
    }

    //    function supplyFloatLiquidity() external pairUnlocked {
    //        // Mints Float pool tokens to the user according to the value supplied
    //        // Value is derived from TWAP pool oracle
    //        // Follows Uniswap model — tokens are pre-sent to the contract by the router.
    //        sync();
    //
    //        // mintFloatTokens()
    //
    //        // Then sends liquidity if it has the appropriate reserves for it
    //        //        _update();
    //    }

    //    function removeFloatLiquidity() external pairUnlocked {
    //        sync();
    //
    //        _extractFloatLiquidity();
    //    }
    //
    //    function supplyAnchorLiquidity() external pairUnlocked {
    //        sync();
    //
    //        _sendLiquidity();
    //    }
    //
    //    function removeAnchorLiquidity() external pairUnlocked {
    //        sync();
    //
    //        _extractAnchorLiquidity();
    //    }
    uint public totalPoolValuePrime;

    function sync() public {
        // TODO: Only continues if it's called by pair itself or if the pair is unlocked
        // Which ensures it's not called within UniswapV2Callee
        console.log("<<<Pylon:sync::::::::start");

        if(msg.sender != pairAddress) { IZirconPair(pairAddress).tryLock(); }

        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula
        (uint112 reserve0, uint112 reserve1,) = IZirconPair(pairAddress).getReserves();

        if (lastPoolTokens != 0 && reserve0 != 0 && reserve1 != 0) {
            uint price;
            uint totalPoolValue;

            uint poolTokensPrime = IZirconPair(pairAddress).totalSupply();
            // total supply could be 0 at the beginning
            uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this));
            // What if pool token balance is 0 ?
            console.log("<<<Pylon:sync::::::::pt'=", poolTokensPrime/testMultiplier, "::::ptb=", poolTokenBalance/testMultiplier);

            // TODO: Don't actually need oracle here, just relatively stable amount of reserve1. Or do we?
            // Adjusted by the protocol's share of the entire pool.
            // price = oracle.getFloatPrice(reserve1, reserve0, floatToken, anchorToken);
            // TODO: SafeMath
            totalPoolValuePrime = reserve0.mul(2).mul(poolTokenBalance)/poolTokensPrime;
            console.log("<<<Pylon:sync::::::::tpv'=", totalPoolValuePrime/testMultiplier);

            uint rootK = Math.sqrt(uint(reserve0).mul(reserve1));
            // TODO: Fix with actual integer math
            // only if lastK > kPrime ?
            console.log("<<<Pylon:sync::::::::lk=", reserve0, reserve1);

            uint rootKLast = Math.sqrt(lastK);

            uint k = rootK.mul(poolTokensPrime)/rootKLast;
            console.log("<<<Pylon:sync::::::::lk=", lastK/testMultiplier);
            console.log("<<<Pylon:sync::::::::k'=", rootK/testMultiplier, ":::k=", k/testMultiplier);
            console.log("<<<Pylon:sync::::::::lpt'=", lastPoolTokens/testMultiplier);
            uint d = (k/lastPoolTokens);
            console.log("<<<Pylon:sync::::::::d=", d);

            uint feeValue = totalPoolValuePrime.mul(d);
            console.log("<<<Pylon:sync::::::::fee=", feeValue/testMultiplier);
            
            virtualAnchorBalance += feeValue.mul(virtualAnchorBalance)/totalPoolValuePrime;
            virtualFloatBalance += feeValue.mul(1-virtualAnchorBalance/totalPoolValuePrime);

            console.log("<<<Pylon:sync::::::::vab'=", virtualAnchorBalance/testMultiplier);
            console.log("<<<Pylon:sync::::::::vfb'=", virtualFloatBalance/testMultiplier);
//            //
//            //            // Gamma is the master variable used to define withdrawals
            gammaMulDecimals = 1 - (virtualAnchorBalance /  totalPoolValuePrime);
            console.log("<<<Pylon:sync::::::::gamma'=", gammaMulDecimals/testMultiplier);
            //            // 1 - ATV/TPV but multiplied by 10**18 due to integer math shit
            console.log("<<<Pylon:sync::::::::end\n\n");

        }
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
