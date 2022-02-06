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
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

// TODO: Create a Pylon Library containing the functions used for calculation
contract ZirconPylon {
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    address public pairAddress;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public pairFactory;
    address public floatPoolToken;
    address public anchorPoolToken;
    address public token0;
    address public token1;
    uint public maxFloatSync;
    uint public maxAnchorSync;

    uint public virtualAnchorBalance; // TODO: make private
    uint public virtualFloatBalance; // TODO: make private
    uint public maximumPercentageSync;

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
    uint private testMultiplier = 1e16;

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

    function getPairReserves()  private view returns  (uint112 _reserve0, uint112 _reserve1) {
        IZirconPair zp = IZirconPair(pairAddress);
        (uint112 _reservePair0, uint112 _reservePair1,) = zp.getReserves();
        _reserve0 = zp.token0() == token0 ? _reservePair0 : _reservePair1;
        _reserve1 = zp.token0() == token0 ? _reservePair1 : _reservePair0;
    }

    // Called once by the factory at time of deployment
    // token0 -> Float token
    // token1 -> Anchor token
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _token0, address _token1, address _pairAddress, address _pairFactory) external {
        require(msg.sender == factory, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolToken = _floatPoolToken;
        anchorPoolToken = _anchorPoolToken;
        pairAddress = _pairAddress;
        token0 = IZirconPair(_pairAddress).token0() == _token0 ? _token0 : _token1;
        token1 = token0 == _token0 ? _token1 : _token0;
        pairFactory = _pairFactory;
        maxFloatSync = ZirconPylonFactory(factory).maxFloat();
        maxAnchorSync = ZirconPylonFactory(factory).maxAnchor();
    }

    // TODO: centralize this
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // TODO: mint AT and FT minus a minimum liquidity in PT
    // TODO: this shit has to be 50-50
    // On init pylon we have to handle to cases
    // The first case is when we initialize the pair through the pylon
    // And the second one is when initialize the pylon with a pair already started
    function initPylon(address _to) external lock{
        console.log("<<<Pylon:_initPylon:::: ");
        require(initialized == 0, "Already Initialized");
        // Let's get the balances so we can see what the user send us
        // As we are initializing the reserves are going to be null
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        require(balance0 > 0 && balance1 > 0, "ZP: Not eough liquidity");
        console.log("<<<Pylon:initPylon::::balance0=", balance0, ":::balance1", balance1);
        // Let's see if the pair contains some reserves
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReserves();
        console.log("<<<Pylon:initPylon::::_reservePair0=", _reservePair0, ":::_reservePair1", _reservePair1);
        // If pair contains reserves we have to use the ratio of the Pair so...
        if (_reservePair0 > 0 && _reservePair1 > 0) {
            // Getting maximum to initialize the vfb and vab variables
            (uint maxX, uint maxY) = _getMaximum(_reservePair0, _reservePair1, balance0, balance1);
            virtualFloatBalance = maxX;
            virtualAnchorBalance = maxY;
            console.log("<<<Pylon:initPylon::::maxX=", maxX, ":::maxY", maxY);
            uint denominator = (virtualAnchorBalance.mul(_reservePair0))/_reservePair1;
            gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));
        }else {
            // Here we initialize the variables of the sync
            virtualAnchorBalance = balance1;
            virtualFloatBalance = balance0;
            uint denominator = (virtualAnchorBalance.mul(balance0))/balance1;
            gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));
        }
        console.log("<<<Pylon:initPylon::::virtualFloatBalance=", virtualFloatBalance, ":::virtualAnchorBalance", virtualAnchorBalance);
        console.log("<<<Pylon:initPylon::::gamma", gammaMulDecimals);
        console.log("<<<Pylon:initPylon::::end\n\n");
        console.log("<<<Pylon:_mintPoolToken::::::::start:anchor");
        // Time to mint some tokens
        _mintPoolToken(balance1, 0, _reservePair1, anchorPoolToken, _to, true);
        console.log("<<<Pylon:_mintPoolToken::::::::start:float");
        _mintPoolToken(balance0, 0, _reservePair0, floatPoolToken, _to, false);
        _update();
        initialized = 1;
    }

    // TODO: check getAmountsOut function of v2 library, they use a slightly different formula
    function _getMaximum(uint _pR0, uint _pR1, uint _b0, uint _b1) pure private returns (uint maxX, uint maxY)  {
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
    function _update() private {
        console.log("<<<Pylon:_update::::::::start");
        // Let's take the current balances
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));

        // Intializing the variables, (Maybe gas consuming let's see how to sort out this
        IZirconPair pair = IZirconPair(pairAddress);
        // Getting peir reserves and updating variables before minting
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReserves();
        // Min0 and Min1 are two variables representing the maximum that can be minted on sync
        // Min0/2 & Min1/2 remains as reserves on the pylon
        // In the case the pair hasn't been initialized pair reserves will be 0 so we take our current balance as the maximum
        uint112 max0 = _pairReserve0 == 0 ? uint112(balance0/maximumPercentageSync) : uint112(_pairReserve0/(maximumPercentageSync));
        uint112 max1 = _pairReserve1 == 0 ? uint112(balance1/maximumPercentageSync) : uint112(_pairReserve1/(maximumPercentageSync));
        console.log("<<<Pylon:balances::::::::", balance0/testMultiplier, balance1/testMultiplier);
        console.log("<<<Pylon:pairReserves::::::::", _pairReserve0/testMultiplier, _pairReserve1/testMultiplier);
        // Pylon Update Minting
        //TODO: check if it is necessary a timeElapsed check
        console.log("<<<Pylon:values::maxes::::::::", max0/testMultiplier, max1/testMultiplier);
        if (balance0 > max0/2 && balance1 > max1/2) {
            console.log("<<<Pylon:values::getMax::::::::", balance0/10**18, balance1/10**18);
            // Get Maximum simple gets the maximum quantity of token that we can mint
            //TODO: Probably we can eliminate this function and calculate this on pairToken basis
            (uint tx, uint ty) = _getMaximum(_pairReserve0 == 0 ? balance0 : _pairReserve0 , _pairReserve1 == 0 ? balance1 :_pairReserve1, balance0.sub(max0/2), balance1.sub(max1/2));
            console.log("<<<Pylon:_getMaximum::::::::", tx/testMultiplier, ty/testMultiplier);

            // Transfering tokens to pair and minting
            if(tx != 0) _safeTransfer(token0, pairAddress, tx);
            if(ty != 0) _safeTransfer(token1, pairAddress, ty);
            pair.mint(address(this));

            // Removing tokens sent to the pair to balances
            balance0 -= tx;
            balance1 -= ty;
        }
        // 2022

        // Let's remove the tokens that are above max0 and max1, and donate them to the pool
        // TODO: Instead of donating we can use async-100% and create some LP tokens for pair
        updateReservesRemovingExcess(balance0, balance1, max0, max1);
        _updateVariables();

        // Updating Variables
        console.log("<<<Pylon:update::::::::end\n\n");

    }

    function _updateVariables() private {

        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReserves();
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        blockTimestampLast = blockTimestamp;
        lastPoolTokens = IZirconPair(pairAddress).totalSupply();
        lastK = uint(_pairReserve0).mul(_pairReserve1);
        console.log("<<<Pylon:_updateVariables::::::::", _pairReserve0, _pairReserve1);

    }

    // Minting
    function _mintFee(uint amount, address poolToken) private returns (bool feeOn){
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        IZirconPoolToken pt = IZirconPoolToken(poolToken);
        feeOn = feeTo != address(0);
        if (feeOn) {
            pt.mint(feeTo, amount);
        }
    }

    function _mintPoolToken(uint _balance, uint112 _pylonReserve, uint112 _pairReserve, address _poolTokenAddress, address _to, bool isAnchor) private returns (uint liquidity) {
        console.log("<<<Pylon:_mintPoolToken::::::::start");
        console.log("<<<Pylon:::::::PairReserve>>>> ", _pairReserve/testMultiplier, "pylonRes::", _pylonReserve/testMultiplier);
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        IZirconPoolToken pt = IZirconPoolToken(_poolTokenAddress);
        uint amountIn = _balance.sub(_pylonReserve);
        console.log("<<<Pylon:::::::amountIn>>>> ", amountIn/testMultiplier);
        uint fee = feeTo != address(0) ? amountIn/1000 : 0;
        console.log("<<<Pylon:::::::fee>>>> ", fee);
        uint toTransfer = amountIn.sub(fee);
        console.log("<<<Pylon:::::::toTransfer>>>> ", toTransfer/testMultiplier);
        require(toTransfer > 0, "ZP: Not Enough Liquidity");

        uint maxSync = (_pairReserve == 0 || _pylonReserve > _pairReserve) ? maxFloatSync :
        (_pairReserve.mul(maximumPercentageSync)/100).sub(_pylonReserve);
        console.log("<<<Pylon:::::::maxSync>>>> ", maxSync/testMultiplier);
        require(maxSync > toTransfer, "ZP: Exceeds");
        // TODO: Maybe safeTransfer the tokens
        uint pts = pt.totalSupply();
        if (pts == 0) pt.mint(address(0), MINIMUM_LIQUIDITY);

        liquidity = calculatePTU(isAnchor, toTransfer, pts);

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
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReserves();

        if (isAnchor) {
            console.log("<<<Pylon:_mintPoolToken::::::::anchor");
            liquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, to, isAnchor);
        }else{
            console.log("<<<Pylon:_mintPoolToken::::::::float");
            liquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, to, isAnchor);
        }
        _update();
    }

    //TODO: Clean up this function
    //TODO: Transfer first then calculate on basis of pool token share how many share we should give to the user
    function mintAsync(address to, bool shouldMintAnchor) external lock isInitialized returns (uint liquidity){
        console.log("<<<Pylon:mintAsync::::::::start");
        sync();
        IZirconPoolToken pt = IZirconPoolToken(shouldMintAnchor ? anchorPoolToken : floatPoolToken);
        IZirconPair pair = IZirconPair(pairAddress);
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReserves();

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint toTransfer0;
        uint toTransfer1;
        uint fee0;
        uint fee1;
        {
            address _token0 = token0;
            address _token1 = token1;
            IZirconPair _pair = pair;
            address feeTo = IUniswapV2Factory(pairFactory).feeTo();
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

        _updateVariables();
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
        console.log("<<<Pylon:sync::::::::start");
        if(msg.sender != pairAddress) { IZirconPair(pairAddress).tryLock(); }
        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula
        (uint112 reserve0, uint112 reserve1) = getPairReserves();
        // If the current K is equal to the last K, means that we haven't had any updates on the pair level
        // So is useless to update any variable because fees on pair haven't changed
        uint currentK = uint(reserve0).mul(reserve1);
        console.log("<<<Pylon:sync::::::::currentK'=", currentK/testMultiplier, "::::lastK=", lastK/testMultiplier);
        //  && lastK < currentK
        if (lastPoolTokens != 0 && reserve0 != 0 && reserve1 != 0) {

            uint poolTokensPrime = IZirconPair(pairAddress).totalSupply();

            // Here it is going to be useful to have a Minimum Liquidity
            // If not we can have some problems
            uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this));
            console.log("<<<Pylon:sync::::::::pt'=", poolTokensPrime/testMultiplier, "::::ptb=", poolTokenBalance/testMultiplier);

            // Let's get the amount of total pool value own by pylon
            totalPoolValuePrime = reserve0.mul(2).mul(poolTokenBalance)/poolTokensPrime;
            console.log("<<<Pylon:sync::::::::tpv'=", totalPoolValuePrime/testMultiplier);
            console.log("<<<Pylon:sync::::::::r0,r1=", reserve0/testMultiplier, reserve1/testMultiplier);

            uint rootK = Math.sqrt(currentK);
            uint d = 1e18 - (Math.sqrt(lastK)*poolTokensPrime*1e18)/(rootK*lastPoolTokens);
            console.log("<<<Pylon:sync::::::::lk=", lastK/testMultiplier);
            console.log("<<<Pylon:sync::::::::lpt'=", lastPoolTokens/testMultiplier);
            console.log("<<<Pylon:sync::::::::d=", d);
            // Getting how much fee value has been created for pylon
            uint feeValue = totalPoolValuePrime.mul(d)/1e18;
            console.log("<<<Pylon:sync::::::::fee=", feeValue/testMultiplier);

            // Calculating gamma, variable used to calculate tokens to mint and withdrawals
            if (virtualAnchorBalance < totalPoolValuePrime/2) {
                gammaMulDecimals = 1e18 - (virtualAnchorBalance*1e18 /  totalPoolValuePrime);
            }else{
                uint denominator = (virtualAnchorBalance.mul(reserve0))/reserve1;
                console.log("<<<Pylon:sync::::::::den=", denominator);
                gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));
            }
            // TODO: (see if make sense to insert a floor to for example 25/75)
            console.log("<<<Pylon:sync::::::::gamma'=", gammaMulDecimals/testMultiplier);
            // Calculating VAB and VFB
            console.log("<<<Pylon:sync:::::::prev:vab'=", virtualAnchorBalance/testMultiplier,
                "<<<Pylon:sync::::::::vfb'=", virtualFloatBalance/testMultiplier);

            virtualAnchorBalance += (feeValue.mul(gammaMulDecimals))/1e18;
            console.log("<<<Pylon:sync::::::::vab'=", virtualAnchorBalance);
            virtualFloatBalance += (1e18-gammaMulDecimals).mul(feeValue)/1e18;
            console.log("<<<Pylon:sync::::::::vfb'=", virtualFloatBalance);
        }
        console.log("<<<Pylon:sync::::::::end\n\n");
    }

    // Called at the end of supply functions to supply any available 50-50 liquidity to underlying pool
    function _sendLiquidity() private { }

    //TODO: send this function to a library
    // On basis of the amount in of tokens this function calculates how many Pool Tokens Shares are given
    function calculatePTU(bool _isAnchor, uint toCalculate, uint _ptTotalSupply) view private returns (uint liquidity){
        (uint112 _reserve0,) = getPairReserves(); // gas savings
        if (_isAnchor) {
            liquidity = _reserve0 == 0 ? toCalculate : ((toCalculate*1e18)/virtualAnchorBalance);
        }else {
            uint numerator = _ptTotalSupply == 0 ? toCalculate.mul(1e18) : toCalculate.mul(_ptTotalSupply);
            uint denominator = _reserve0 == 0 ? gammaMulDecimals.mul(2) : (_reserve0.mul(gammaMulDecimals).mul(2))/1e18;
            liquidity = numerator/denominator;
        }
    }

    //TODO: send this function to a library
    // TODO: sistema di slashing, not withdraw more than a total
    function calculateLPTU(bool _isAnchor, uint _liquidity, uint _ptTotalSupply) view private returns (uint claim){
        console.log("<<<<_liquidity", _liquidity);

    (uint112 _reserve0, uint112 _reserve1) = getPairReserves(); // gas savings
        uint ptb = IZirconPair(pairAddress).balanceOf(address(this));
        uint share1 = _liquidity*1e18/_ptTotalSupply;
        console.log("<<<<share1", share1);

        if (_isAnchor) {
            uint share = (ptb.mul(virtualAnchorBalance))/(2*_reserve1);
            console.log("<<<<share", share);
            claim = (share.mul(share1))/1e18;
        }else{
            uint share = (gammaMulDecimals.mul(ptb))/(2*_reserve0);
            console.log("<<<<share", share);
            claim = (share.mul(share1))/1e18;
        }
        require(claim > 0, 'ZP: INSUFFICIENT_LIQUIDITY_BURNED');
        console.log("<<<<ptb", ptb);
        console.log("<<<<claim", claim);
    }

    //TODO: send this function to a library
    function calculatePTUToAmount(bool _isAnchor, uint _ptuAmount, uint _totalSupply) view private returns (uint amount) {
        (uint112 _reserve0,) = getPairReserves(); // gas savings
        if (_isAnchor) {
            amount = virtualAnchorBalance.mul(_ptuAmount)/1e18;
        } else {
            uint numerator = (_ptuAmount.mul(gammaMulDecimals)*2)/1e18;
            amount = numerator.mul(_reserve0)/_totalSupply;
        }
        console.log("<<<::: amount", amount);

    }

    function burn(address to, bool isAnchor) external lock{
        sync();
        console.log("<<<<extract start");
        // Selecting the Pool Token class on basis of the requested tranch to burn
        IZirconPoolToken pt = IZirconPoolToken(isAnchor ? anchorPoolToken : floatPoolToken);
        (uint112 _reserve0, uint112 _reserve1) = getPairReserves(); // gas savings
        console.log("<<<<r0", _reserve0, "<<<r1", _reserve1);
        {
            address _token0 = token0;                                // gas savings
            address _token1 = token1;                                // gas savings
            // Let's get how much liquidity was sent to burn
            uint liquidity = pt.balanceOf(address(this));
            console.log("<<<<liquidity", liquidity);
            bool _isAnchor = isAnchor;
            address _to = to;
            address _pairAddress = pairAddress;
            (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getReserves(); // gas savings
            uint _totalSupply = pt.totalSupply();
            // Here we calculate the PTU for the reserve used
            console.log("<<< calculatingReservesPTU");
            uint reservePTU = calculatePTU(_isAnchor, _isAnchor ? _pylonReserve1 : _pylonReserve0, _totalSupply);
            console.log("<<< calculatePTUToAmount", reservePTU);
            _safeTransfer(_isAnchor ? _token1 : _token0, _to, calculatePTUToAmount(_isAnchor, Math.min(reservePTU, liquidity), _totalSupply));
            if (reservePTU < liquidity) {
                console.log("<<< calculateLPTU");
                _safeTransfer(_pairAddress, _pairAddress, calculateLPTU(_isAnchor, liquidity.sub(reservePTU), _totalSupply));
                IZirconPair(_pairAddress).burnOneSide(_to, IZirconPair(_pairAddress).token0() == _token0 && !_isAnchor);
            }
            pt.burn(address(this), liquidity);
        }
        console.log("<<<<extract end\n\n");
        _update();


        //        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        //        emit Burn(msg.sender, amount0, amount1, to);
    }

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
