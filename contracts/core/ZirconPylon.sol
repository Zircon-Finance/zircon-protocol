pragma solidity ^0.5.16;
import './libraries/Math.sol';
import './interfaces/IZirconPair.sol';
import './interfaces/IZirconPoolToken.sol';
import "./libraries/SafeMath.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/ZirconLibrary.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IZirconPylonFactory.sol";
//import "hardhat///console.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

contract ZirconPylon {
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    struct PylonToken {
        address float;
        address anchor;
    }
    bool public isFloatReserve0;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    address public pairAddress;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public pairFactory;
    address public floatPoolToken;
    address public anchorPoolToken;

    PylonToken public pylonToken;

    uint public virtualAnchorBalance; // TODO: make private
    uint public virtualFloatBalance; // TODO: make private
    uint public maximumPercentageSync;
    uint public dynamicFeePercentage;

    uint public gammaMulDecimals; // Name represents the fact that this is always the numerator of a fraction with 10**18 as denominator.
    uint public lastK;
    uint public lastPoolTokens;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves (always anchor)
    uint112 private reserve1;           // us es single storage slot, accessible via getReserves (always float)
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves
    uint public initialized = 0;
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

    event PylonUpdate(uint _reserve0, uint _reserve1);
    event PylonSync(uint _vab, uint _vfb, uint _gamma);
    event MintSync(address sender, uint aIn0);
    event MintAsync(address sender, uint aIn0, uint aIn1);
    event MintAsync100(address sender, uint aIn0);
    event Burn(address sender, uint aIn0);
    event BurnAsync(address sender, uint aIn0, uint aIn1);
    event Excess(uint aIn0, bool isAnchor);

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
    }

    function getSyncReserves()  public view returns  (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    // Function that returns correctly
    // Float -> reserve0
    // Anchor -> reserve1
    function getPairReservesNormalized()  private view returns  (uint112 _reserve0, uint112 _reserve1) {
        (uint112 _reservePair0, uint112 _reservePair1,) = IZirconPair(pairAddress).getReserves();
        _reserve0 = isFloatReserve0 ? _reservePair0 : _reservePair1;
        _reserve1 = isFloatReserve0 ? _reservePair1 : _reservePair0;
    }

    // Called once by the factory at time of deployment
    // @_floatPoolToken -> Contains Address Of Float PT
    // @_anchorPoolToken -> Contains Address Of Anchor PT
    // @floatToken -> Float token
    // @anchorToken -> Anchor token
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _floatToken, address _anchorToken, address _pairAddress, address _pairFactory) external {
        require(msg.sender == factory, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolToken = _floatPoolToken;
        anchorPoolToken = _anchorPoolToken;
        pairAddress = _pairAddress;
        isFloatReserve0 = IZirconPair(_pairAddress).token0() == _floatToken;
        // In Pair we save token0 and anchorToken
        //By definition token0 is Float and anchorToken is Anchor
        pylonToken = PylonToken(_floatToken, _anchorToken);
        pairFactory = _pairFactory;
        // Retrieving maximum sync from ZPF

        maximumPercentageSync = IZirconPylonFactory(factory).maximumPercentageSync();
        dynamicFeePercentage = IZirconPylonFactory(factory).dynamicFeePercentage();
    }

    // On init pylon we have to handle two cases
    // The first case is when we initialize the pair through the pylon
    // And the second one is when initialize the pylon with a pair already existing
    function initPylon(address _to) external lock {
        require(initialized == 0, "Already Initialized");

        // Let's get the balances so we can see what the user send us
        // As we are initializing the reserves are going to be null

        uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
        require(balance0 > 0 && balance1 > 0, "ZP: Not enough liquidity");


        // Let's see if the pair contains some reserves
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        // If pair contains reserves we have to use the ratio of the Pair so...

        virtualFloatBalance = balance0;
        virtualAnchorBalance = balance1;
        uint denominator;
        if (_reservePair0 > 0 && _reservePair1 > 0) {
            // Getting maximum to initialize the VFB and VAB variables
            // (uint maxX, uint maxY) = ZirconLibrary._getMaximum(_reservePair0, _reservePair1, balance0, balance1);
            // Todo: Check Potential edge case when users supply imbalanced tokens
            //            //console.log("<<<Pylon:initPylon::::maxX=", maxX, ":::maxY", maxY);
            denominator = (virtualAnchorBalance.mul(_reservePair0))/_reservePair1;
            //This is gamma formula when FTV <= 50%
        } else {
            // Here we initialize the variables of the sync
            denominator = (virtualAnchorBalance.mul(balance0))/balance1;
        }


        //TODO: Old definition of gamma, necessary because pool may not be initialized but check for weird interactions
        gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));


        // Time to mint some tokens
        _mintPoolToken(balance1, 0, _reservePair1, anchorPoolToken, _to, true);
        _mintPoolToken(balance0, 0, _reservePair0, floatPoolToken, _to, false);

        //Here it updates the state and throws liquidity into the pool if possible
        _update();
        initialized = 1;
    }


    // This function takes
    // @balance0 & @balance1 -> The New Balances After A Sync Update
    // @max0 & @max1 -> The maximum that we can save on the reserves
    // If we have any excess reserves we donate them to the pool

    //Todo: Function should be fine although the mintOneSide usage could be dangerous
    //Todo: But we need to check how we use it.
    function updateReservesRemovingExcess(uint newReserve0, uint newReserve1, uint112 max0, uint112 max1) private {
        if (max0 < newReserve0) {
            _safeTransfer(pylonToken.float, pairAddress, uint112(newReserve0.sub(max0)));
            IZirconPair(pairAddress).mintOneSide(address(this), isFloatReserve0);
            reserve0 = max0;
        } else {
            reserve0 = uint112(newReserve0);
        }
        if (max1 < newReserve1) {
            _safeTransfer(pylonToken.anchor, pairAddress, uint112(newReserve1.sub(max1)));
            IZirconPair(pairAddress).mintOneSide(address(this), !isFloatReserve0);
            reserve1 = max1;
        }else{
            reserve1 = uint112(newReserve1);
        }
        emit PylonUpdate(reserve0, reserve1);
    }

    function translateToPylon(uint toConvert, uint errorReturn) view private returns (uint amount){
        uint ptb = IZirconPair(pairAddress).balanceOf(address(this));
        uint ptt = IZirconPair(pairAddress).totalSupply();
        amount =  (ptt == 0 || ptb == 0) ? errorReturn : toConvert.mul(ptb)/ptt;
    }


    // Update reserves and, on the first call per block, price accumulator
    // Any excess of balance is going to be donated to the pair
    // So... here we get the maximum off both tokens and we mint Pool Tokens

    //Sends pylonReserves to pool if there is a match
    function _update() private {
        // Let's take the current balances
        uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));

        // Intializing the variables, (Maybe gas consuming let's see how to sort out this
        // Getting peir reserves and updating variables before minting
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();

        // Max0 and Max1 are two variables representing the maximum that can be minted on sync
        // Min0/2 & Min1/2 remain as reserves on the pylon
        // In the case the pair hasn't been initialized pair reserves will be 0 so we take our current balance as the maximum
        uint reservesTranslated0 = translateToPylon(_pairReserve0, balance0);
        uint reservesTranslated1 = translateToPylon(_pairReserve1, balance1);

        uint112 max0 = _pairReserve0 == 0 ? uint112(balance0.mul(maximumPercentageSync)/100) : uint112(reservesTranslated0.mul(maximumPercentageSync)/100);
        uint112 max1 = _pairReserve1 == 0 ? uint112(balance1.mul(maximumPercentageSync)/100) : uint112(reservesTranslated1.mul(maximumPercentageSync)/100);
        // Pylon Update Minting
        //TODO: check if it is necessary a timeElapsed check
        if (balance0 > max0/2 && balance1 > max1/2) {
            // Get Maximum simple gets the maximum quantity of token that we can mint
            (uint px, uint py) = ZirconLibrary._getMaximum(
                _pairReserve0 == 0 ? balance0 : _pairReserve0,
                _pairReserve1 == 0 ? balance1 : _pairReserve1,
                balance0.sub(max0/2), balance1.sub(max1/2));
            // Transferring tokens to pair and minting
            if(px != 0) _safeTransfer(pylonToken.float, pairAddress, px);
            if(py != 0) _safeTransfer(pylonToken.anchor, pairAddress, py);
            IZirconPair(pairAddress).mint(address(this));
            // Removing tokens sent to the pair to balances
            balance0 -= px;
            balance1 -= py;
        }
        // 2022

        // Let's remove the tokens that are above max0 and max1, and donate them to the pool
        // This is for cases where somebody just donates tokens to pylon; tx reverts if this done via core functions
        //Todo: This is likely also invoked if the price dumps and the sync pool is suddenly above max, not ideal behavior...

        updateReservesRemovingExcess(balance0, balance1, max0, max1);
        _updateVariables();

        // Updating Variables
    }
    // This Function is called to update some variables needed for calculation
    //Todo: This seems wrong, updating these variables without syncing would essentially skip a key state transition.
    //Todo: Likely that we need to replace all uses of this with sync()
    function _updateVariables() private {
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        blockTimestampLast = blockTimestamp;
        lastPoolTokens = IZirconPair(pairAddress).totalSupply();
        lastK = uint(_pairReserve0).mul(_pairReserve1);
    }

    // Minting Fee
    // @amount and @poolToken
    function _mintFee(uint amount, address poolToken) private returns (bool minted){
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        minted = feeTo != address(0);
        if (minted) {
            IZirconPoolToken(poolToken).mint(feeTo, amount);
        }
    }



    // Mint Pool Token
    // @_balance -> Balance OF PT
    // @_pylonReserve -> Reserves of PT on Pylon
    function _mintPoolToken(uint _balance, uint112 _pylonReserve, uint112 _pairReserve, address _poolTokenAddress, address _to, bool isAnchor) private returns (uint liquidity) {
        uint amountIn = _balance.sub(_pylonReserve);

        require(amountIn > 0, "ZP: Not Enough Liquidity");
        uint pts = IZirconPoolToken(_poolTokenAddress).totalSupply();
        {
            // TODO: Clean up this to avoid using hardcoded values
            uint pylonReserve = _pylonReserve;
            uint pairReserve = _pairReserve;
            uint pairReserveTranslated = translateToPylon(pairReserve, 0);

//            uint maxSync = (pairReserveTranslated == 0 || pairReserve == 0 || _pylonReserve > pairReserveTranslated) ? amountIn :
//            (pairReserveTranslated.mul(maximumPercentageSync)/100).sub(_pylonReserve);
//            //console.log("MintPoolTokens:: MaxSync:: AmountIn::",maxSync, amountIn );
//            require(maxSync >= amountIn, "ZP: Exceeds max sync pool");

            uint _gamma = gammaMulDecimals;
            uint _vab = virtualAnchorBalance;

            // When @pts is null we mint some liquidity to null address to ensure pt is never 0
            if (pts == 0) IZirconPoolToken(_poolTokenAddress).mint(address(0), MINIMUM_LIQUIDITY);

//            //console.log("<<<_mintPoolToken: (Before calculatePTU) isAnchor: ", isAnchor);
//            //console.log("<<<_mintPoolToken: amountIn: ", amountIn);
//            //console.log("<<<_mintPoolToken: pts: ", pts);
//            //console.log("<<<_mintPoolToken: pairReserve: ", pairReserve);
//            //console.log("<<<_mintPoolToken: pylonReserve: ", pylonReserve);
//            //console.log("<<<_mintPoolToken: gamma: ", _gamma);
//            //console.log("<<<_mintPoolToken: vab: ", _vab);

            liquidity = ZirconLibrary.calculatePTU(isAnchor, amountIn, pts, pairReserveTranslated, pylonReserve, _gamma, _vab);

//            //console.log("<<<_mintPoolToken: liquidity to mint: ", liquidity);

        }

        if(pts != 0){
            // When pts is null we don't update @vab and @vfb because in the init are already updated
            if(isAnchor) {
                virtualAnchorBalance += amountIn;
            }else{
                virtualFloatBalance += amountIn;
            }
        }

        //Todo: This is 5%, change
        uint fee = liquidity.mul(dynamicFeePercentage)/100;
        if(_mintFee(fee, _poolTokenAddress)) {
            liquidity -= fee;
         }
        IZirconPoolToken(_poolTokenAddress).mint(_to, liquidity);

        emit MintSync(msg.sender, amountIn);
//        //console.log("<<<Pylon:_mintPoolToken::::::::end", liquidity);
    }
    // External Function called to mint pool Token
    // Liquidity have to be sent before
    // TODO: recheck in dump scenario if sync pool can be blocked

    //aka syncMint
    function mintPoolTokens(address to, bool isAnchor) isInitialized external returns (uint liquidity) {
        sync();
        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves();
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        //Mints pool tokens regardless of reserve situation
        //_mintPoolToken(uint _balance, uint112 _pylonReserve, uint112 _pairReserve, address _poolTokenAddress, address _to, bool isAnchor) private returns (uint liquidity)

        if (isAnchor) {

            uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
            liquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, to, isAnchor);
            ////console.log("MintPoolTokens ended, liquidity & initial totalSupply", liquidity, IZirconPoolToken(anchorPoolToken).totalSupply());
        }else{
            uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            liquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, to, isAnchor);
            //console.log("MintPoolTokens ended, liquidity & initial totalSupply", liquidity, IZirconPoolToken(floatPoolToken).totalSupply());
        }



        //Sends tokens into pool if there is a match
        _update();

    }


    //Helper function to calculate slippage-adjusted share of pool
    function _disincorporateAmount(uint _amountIn, bool isAnchor) private returns (uint amount0, uint amount1) {
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        amount0 = !isAnchor ? _amountIn/2 : ZirconLibrary.getAmountOut(_amountIn/2, _reservePair1, _reservePair0);
        amount1 = isAnchor ? _amountIn/2 : ZirconLibrary.getAmountOut(_amountIn/2, _reservePair0, _reservePair1);
    }

    function mintAsync100(address to, bool isAnchor) isInitialized external returns (uint liquidity) {
//        //console.log("<<<_mintAsync100: gamma before Sync: ", gammaMulDecimals/testMultiplier);
        sync();
//        //console.log("<<<_mintAsync100: gamma after Sync: ", gammaMulDecimals/testMultiplier);
        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves();

        uint amountIn;
        if (isAnchor) {

            uint balance = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
//            //console.log("<<<_mintAsync100: balance: ", balance/testMultiplier, reserve1/testMultiplier);

            amountIn = balance.sub(_reserve1);
        }else{
            uint balance = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            amountIn = balance.sub(_reserve0);
        }
//        //console.log("<<<_mintAsync100: totalUniV2PTBefore: ", IZirconPair(pairAddress).totalSupply() / testMultiplier);
//        //console.log("<<<_mintAsync100: amountInUni: ", amountIn / testMultiplier);
        require(amountIn > 0, "ZP: INSUFFICIENT_AMOUNT");
        _safeTransfer(isAnchor ? pylonToken.anchor : pylonToken.float, pairAddress, amountIn);
        bool shouldTakeReserve0 = isFloatReserve0 ? !isAnchor : isAnchor;
        {
            (uint a0, uint a1) = _disincorporateAmount(amountIn, isAnchor);
//            //console.log("<<<_mintAsync100: amountOut0: ", a0 / testMultiplier);
//            //console.log("<<<_mintAsync100: amountOut1: ", a1 / testMultiplier);

            liquidity = getLiquidityFromPoolTokens(
                a0, a1,
                isAnchor,
                IZirconPoolToken(isAnchor ? anchorPoolToken : floatPoolToken));
            (uint liq,,) = IZirconPair(pairAddress).mintOneSide(address(this), shouldTakeReserve0);
            IZirconPoolToken(isAnchor ? anchorPoolToken : floatPoolToken).mint(to, liquidity);
        }//TODO: This only updates k and pt supply, doesn't re-sync
        _updateVariables();

        emit MintAsync100(msg.sender, amountIn);
    }

    function getLiquidityFromPoolTokens(uint amountIn0, uint amountIn1,  bool shouldMintAnchor, IZirconPoolToken pt) private returns (uint liquidity){
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();
        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves(); // gas savings

        if (shouldMintAnchor) {
            uint amountInAdjusted = Math.min((amountIn0.mul(_pairReserve1).mul(2))/_pairReserve0, amountIn1.mul(2)); //Adjust AmountIn0 to its value in Anchor tokens
            //console.log(">>amountInAdjusted>>", amountInAdjusted);
            liquidity = ZirconLibrary.calculatePTU(shouldMintAnchor, amountInAdjusted, pt.totalSupply(), translateToPylon(_pairReserve1, 0), _reserve1, gammaMulDecimals, virtualAnchorBalance);
            virtualAnchorBalance += amountInAdjusted;
            //liquidity = (amountInAdjusted.mul(pt.totalSupply()))/virtualAnchorBalance;
        }else{
            uint amountInAdjusted = Math.min((amountIn1.mul(_pairReserve0).mul(2))/_pairReserve1, amountIn0.mul(2)); //Adjust AmountIn1 to its value in Float tokens
            //console.log(">>amountInAdjusted>>", amountInAdjusted);
            liquidity = ZirconLibrary.calculatePTU(shouldMintAnchor, amountInAdjusted, pt.totalSupply(), translateToPylon(_pairReserve0, 0), _reserve0, gammaMulDecimals, virtualAnchorBalance);
            virtualFloatBalance += amountInAdjusted;

            //liquidity = amountInAdjusted.mul(pt.totalSupply())*1e18/(_pairReserve0.mul(2).mul(gammaMulDecimals));
            // Todo: Change toTransfer (probably remove?)
        }
    }

    //TODO: Transfer first then calculate on basis of pool token share how many share we should give to the user
    function mintAsync(address to, bool shouldMintAnchor) external lock isInitialized returns (uint liquidity){
        //console.log("Mint Async gamma before sync::: ", gammaMulDecimals/testMultiplier);
        sync();
//        //console.log("Mint Async gamma after::: ", gammaMulDecimals/testMultiplier);
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
//        //console.log("Mint Async::: ", gammaMulDecimals/testMultiplier);
        address _poolTokenAddress = shouldMintAnchor ? anchorPoolToken : floatPoolToken;

        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves(); // gas savings
        uint amountIn0;
        uint amountIn1;
        {
            uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
//            //console.log("<<<Pylon:float balance & syncReserve::::::::", balance0/testMultiplier, reserve0/testMultiplier);
//            //console.log("<<<Pylon:anchor balance & syncReserve::::::::", balance1/testMultiplier, reserve1/testMultiplier);
            amountIn0 = balance0.sub(_reserve0);
            amountIn1 = balance1.sub(_reserve1);
//            //console.log("<<<Pylon:amount in 0 and 1::::::::", amountIn0, amountIn1);
            liquidity = getLiquidityFromPoolTokens(amountIn0, amountIn1, shouldMintAnchor, IZirconPoolToken(_poolTokenAddress));
//            //console.log("Mint Async liquidity::: ", liquidity);
//            //console.log("Mint Async total pool tokens::: ", IZirconPoolToken(_poolTokenAddress).totalSupply()/testMultiplier);

        }

        require(amountIn1 > 0 && amountIn0 > 0, "ZirconPylon: Not Enough Liquidity");
        _safeTransfer(pylonToken.float, pairAddress, amountIn0);
        _safeTransfer(pylonToken.anchor, pairAddress, amountIn1);
        ////console.log("Mint Async total Uni V2 liquidity::: ", IZirconPair(pairAddress).totalSupply());
        (uint l) = IZirconPair(pairAddress).mint(address(this));
        ////console.log("Mint Async minted Uni V2 liquidity::: ", l);


        // uint deltaSupply = pair.totalSupply().sub(_totalSupply);
        // TODO: maybe another formula is faster
        // TODO: check maximum to mint

        //TODO: Change fee
        {
            uint fee =  liquidity.mul(dynamicFeePercentage)/100;
            if (_mintFee(fee, _poolTokenAddress)){
                liquidity -= fee;
            }
            IZirconPoolToken(_poolTokenAddress).mint(to, liquidity);
        }
        emit MintAsync(msg.sender, amountIn0, amountIn1);

        //console.log("<<<Pylon:mintAsync::::::::", liquidity);

        _updateVariables();
    }

    function sync() private {

        //Prevents this from being called while the underlying pool is getting flash loaned
        if(msg.sender != pairAddress) { IZirconPair(pairAddress).tryLock(); }

        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula

        (uint112 pairReserve0, uint112 pairReserve1) = getPairReservesNormalized();
        (uint112 pylonReserve0, uint112 pylonReserve1,) = getSyncReserves();

        // If the current K is equal to the last K, means that we haven't had any updates on the pair level
        // So is useless to update any variable because fees on pair haven't changed
        uint currentK = uint(pairReserve0).mul(pairReserve1);
//        //console.log("<<<Pylon:sync()::::::::pairReserve0: ", pairReserve0, pylonReserve0); //" pairReserve1: ", pairReserve1, " currentK: ", currentK, "lastK: ", lastK);
//        //console.log("<<<Pylon:sync()::::::::pairReserve1: ", pairReserve1, pylonReserve1); //" pairReserve1: ", pairReserve1, " currentK: ", currentK, "lastK: ", lastK);
//        //console.log("<<<Pylon:sync()::::::::currentK: ", currentK); //" pairReserve1: ", pairReserve1, " currentK: ", currentK, "lastK: ", lastK);
//        //console.log("<<<Pylon:sync()::::::::lastK: ", lastK);

        //  && lastK < currentK
        if (lastPoolTokens != 0 && pairReserve0 != 0 && pairReserve1 != 0) {

            uint poolTokensPrime = IZirconPair(pairAddress).totalSupply();

            // Here it is going to be useful to have a Minimum Liquidity
            // If not we can have some problems
            // uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this));

            // Let's get the amount of total pool value own by pylon

            //TODO: Add system that accumulates fees to cover insolvent withdrawals (and thus changes ptb)

            uint totalPoolValueAnchorPrime = translateToPylon(pairReserve1.mul(2), 0); // .mul(poolTokenBalance)/poolTokensPrime;
            uint totalPoolValueFloatPrime = translateToPylon(pairReserve0.mul(2), 0); // .mul(poolTokenBalance)/poolTokensPrime;
            ////console.log("<<<Pylon:sync::::::::tpv'=", totalPoolValueAnchorPrime/testMultiplier);
            ////console.log("<<<Pylon:sync::::::::r0,r1=", pairReserve0/testMultiplier, pairReserve1/testMultiplier);
            uint one = 1e18;
            uint d = (one).sub((Math.sqrt(lastK)*poolTokensPrime*1e18)/(Math.sqrt(currentK)*lastPoolTokens));
            ////console.log("<<<Pylon:sync::::::::lk=", lastK/testMultiplier);
            ////console.log("<<<Pylon:sync::::::::lpt'=", lastPoolTokens/testMultiplier);
            ////console.log("<<<Pylon:sync::::::::d=", d);
            // Getting how much fee value has been created for pylon
            uint feeValueAnchor = totalPoolValueAnchorPrime.mul(d)/1e18;
            uint feeValueFloat = totalPoolValueFloatPrime.mul(d)/1e18;
            ////console.log("<<<Pylon:sync::::::::fee=", feeValueAnchor/testMultiplier);



            // Calculating gamma, variable used to calculate tokens to mint and withdrawals
            ////console.log("<<<Pylon:sync:::::::prev:vab'=", virtualAnchorBalance/testMultiplier,
            //    "<<<Pylon:sync::::::::vfb'=", virtualFloatBalance/testMultiplier);

            //gamma is supposed to always be an accurate reflection of the float share as a percentage of the totalPoolValue
            //however vfb also includes the syncPool reserve portion, which is completely outside of the pools.
            //Nonetheless, the syncPool is still considered part of the user base/float share.
            //This is relevant primarily for fee calculations, but that's already a given: you just use the same proportions.
            //In all other places we (should) already account for the sync pool separately.

            //When operating on fractional, gamma is higher than it should be compared to ftv + atv.
            //This means that anchors get more fees than they "should", which kinda works out because they're at high risk.
            //It works as an additional incentive to not withdraw.
//            //console.log("<<<sync(): vab: ", virtualAnchorBalance);
//            //console.log("<<<sync(): vfb: ", virtualFloatBalance);
            virtualAnchorBalance += ((feeValueAnchor.mul(gammaMulDecimals))/1e18);



            virtualFloatBalance += ((1e18-gammaMulDecimals).mul(feeValueFloat)/1e18);

//            //console.log("<<<sync(): lastPoolTokens: ", lastPoolTokens);
//            //console.log("<<<sync(): feeA: ", feeValueAnchor);
//            //console.log("<<<sync(): feeF: ", feeValueFloat);
//            //console.log("<<<sync(): ptt: ", IZirconPair(pairAddress).totalSupply());
//            //console.log("<<<sync(): ptb: ", IZirconPair(pairAddress).balanceOf(address(this)));
//            //console.log("<<<sync(): att: ", IZirconPoolToken(anchorPoolToken).totalSupply());
//            //console.log("<<<sync(): ftt: ", IZirconPoolToken(floatPoolToken).totalSupply());
//            //console.log("<<<sync(): vab: ", virtualAnchorBalance);
//            //console.log("<<<sync(): vfb: ", virtualFloatBalance);
//            //console.log("<<<sync(): TPVFloatPrime: ", totalPoolValueFloatPrime);
//            //console.log("<<<sync(): TPVAnchorPrime: ", totalPoolValueAnchorPrime    );
//            //console.log("<<<sync(): Price of Float: ", (pairReserve1*1e18/pairReserve0));

            if ((virtualAnchorBalance.sub(pylonReserve1)) < totalPoolValueAnchorPrime/2) {
                gammaMulDecimals = 1e18 - ((virtualAnchorBalance.sub(pylonReserve1))*1e18 /  totalPoolValueAnchorPrime);
                //console.log("<<<sync(): Case 1, gamma: ", gammaMulDecimals/testMultiplier, virtualAnchorBalance/testMultiplier, pylonReserve1/testMultiplier);
                ////console.log("<<<Pylon:sync::::::::gammaAnchor'=", gammaMulDecimals/testMultiplier);

            } else {
                //TODO: Check that this works and there are no gamma that assume gamma is ftv/atv+ftv



                gammaMulDecimals = ((virtualFloatBalance.sub(pylonReserve0)) *1e18) /  totalPoolValueFloatPrime;
                //console.log("<<<sync(): Case 2, gamma: ", gammaMulDecimals, virtualFloatBalance/testMultiplier, pylonReserve0/testMultiplier);
                ////console.log("<<<Pylon:sync::::::::gammaFloat'=", gammaMulDecimals/testMultiplier);

            }
            // TODO: (see if make sense to insert a floor to for example 25/75)


            //Sync pool also gets a claim to these

            ////console.log("<<<Pylon:sync::::::::vfb'=", virtualFloatBalance, "vab", virtualAnchorBalance);

            emit PylonSync(virtualAnchorBalance, virtualFloatBalance, gammaMulDecimals);
        }
        //console.log("<<<Pylon:sync::::::::end\n\n");
    }

    function calculateLPTU(bool _isAnchor, uint _liquidity, uint _ptTotalSupply) view private returns (uint claim){
        (uint112 _reserve0, uint112 _reserve1) = getPairReservesNormalized(); // gas savings
        (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getSyncReserves(); // gas savings
        uint pylonShare;
        if (_isAnchor) {
            pylonShare = (IZirconPair(pairAddress).balanceOf(address(this)).mul(virtualAnchorBalance.sub(_pylonReserve1)))/(2*uint(translateToPylon(_reserve1, 1)));
            //Adjustment factor to extract correct amount of liquidity
            pylonShare = pylonShare.add(pylonShare.mul(_pylonReserve1)/(translateToPylon(_reserve1.mul(2), 1)));
        }else{
            pylonShare = ((gammaMulDecimals).mul(IZirconPair(pairAddress).balanceOf(address(this))))/1e18;
            pylonShare = pylonShare.add(pylonShare.mul(_pylonReserve0)/(translateToPylon(_reserve0.mul(2), 1)));
        }
        ////console.log("<<<<claim", _liquidity);
        //Liquidity/pt applies share over pool + reserves to something that is just pool. So it gives less liquidity than it should
        claim = (_liquidity.mul(pylonShare))/_ptTotalSupply;
        ////console.log("<<<<claim", claim);
        require(claim > 0, 'ZP: INSUFFICIENT_LIQUIDITY_BURNED');
    }

     // Burn Async send both tokens 50-50
     // Liquidity has to be sent before
    //Old
    function burnAsync(address _to, bool _isAnchor) external lock returns (uint amount0, uint amount1){
        sync();

        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
        uint liquidity = pt.balanceOf(address(this));
        uint ptTotalSupply = pt.totalSupply();

        ////console.log("burnAsync liquidity & Zircon pool token supply", liquidity, pt.totalSupply());
        require(liquidity > 0, "ZP: Not enough liquidity inserted");

        uint omegaMulDecimals = 1e18;

        {
            (uint reserveFloat, uint reserveAnchor,) = getSyncReserves();
            (uint pairReserves0, uint pairReserves1) = getPairReservesNormalized();

            {
                //Calculates max liquidity to avoid withdrawing portion in sync pools

                uint maxPoolTokens = _isAnchor ?
                ptTotalSupply - ptTotalSupply.mul(reserveAnchor) / virtualAnchorBalance :
                ptTotalSupply - ptTotalSupply.mul(reserveFloat) / (pairReserves0.mul(2).mul(gammaMulDecimals) / 1e18).add(reserveFloat);

                require(liquidity < maxPoolTokens, "ZP: Exceeded Burn Async limit");
            }
            //Anchor slashing logic


            if (_isAnchor) {

                //Omega is the slashing factor. It's always equal to 1 if pool has gamma above 50%
                //If it's below 50%, it begins to go below 1 and thus slash any withdrawal.
                //Note that in practice this system doesn't activate unless the syncReserves are empty.
                //Also note that a dump of 60% only generates about 10% of slashing.
                ////console.log("<<<<translateToPylon", translateToPylon(pairReserves1.mul(2), 0));

                omegaMulDecimals = ZirconLibrary.slashLiabilityOmega(
                    translateToPylon(pairReserves1.mul(2), 0),
                    reserveAnchor,
                    gammaMulDecimals,
                    virtualAnchorBalance);
            }
        }


        uint adjustedLiquidity = liquidity.mul(omegaMulDecimals)/1e18;
//        //console.log("adjustedLiquidity", adjustedLiquidity);
//        //console.log("ptTotalSupply", ptTotalSupply);
//        //console.log("vab", virtualAnchorBalance);
//        //console.log("gamma", gammaMulDecimals);


        uint ptu = calculateLPTU(_isAnchor, adjustedLiquidity, ptTotalSupply);
        //console.log("BurnAsync: PTU", ptu);
        //console.log("BurnAsync: PTB", IZirconPair(pairAddress).balanceOf(address(this)));

        _safeTransfer(pairAddress, pairAddress, ptu);
        (uint amountA, uint amountB) = IZirconPair(pairAddress).burn(_to);
        amount0 = isFloatReserve0 ? amountA : amountB;
        amount1 = isFloatReserve0 ? amountB : amountA;


        //console.log("<<<<omegaMulDecimals", omegaMulDecimals);

//        //console.log("amount0", amount0);
//        //console.log("amount1", amount1);

        if(_isAnchor) {

            ////console.log("BurnAsync Anchor, oldVAB & Amount: ", virtualAnchorBalance, amount0.mul(2));
            virtualAnchorBalance -= virtualAnchorBalance.mul(liquidity)/ptTotalSupply;
            ////console.log("Burn async vab after reduction: ", virtualAnchorBalance);
        } else {

            //We reduce vab and vfb proportionally to liquidity due to e.g. float share being higher than vfb
            ////console.log("BurnAsync Float, oldVfB & reductionAmount: ", virtualFloatBalance, amount1.mul(2));
            virtualFloatBalance -= virtualFloatBalance.mul(liquidity)/ptTotalSupply;
            ////console.log("Burn async vfb after reduction: ", virtualFloatBalance);
        }

        ////console.log("vab new", virtualAnchorBalance);
        ////console.log("vfb new", virtualFloatBalance);

        //Burns the Zircon pool tokens
        pt.burn(address(this), liquidity);
        _updateVariables();

        emit BurnAsync(msg.sender, amount0, amount1);

    }

    // Function That calculates the amount of reserves in PTU
    // and the amount of the minimum from liquidity and reserves
    // Helper function for burn
    function preBurn(bool isAnchor, uint _totalSupply, uint _liquidity) view private returns (uint reservePT, uint amount) {
        // variables declaration
        uint _gamma = gammaMulDecimals;
        uint _vab = virtualAnchorBalance;
        (uint112 _reserve0, uint112 _reserve1) = getPairReservesNormalized(); // gas savings
        (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getSyncReserves();

        //Calculates maxPTs that can be serviced through Pylon Reserves


        uint pylonReserve = isAnchor ? _pylonReserve1 : _pylonReserve0;
        uint reserve = isAnchor ? reserve1 : _reserve0;
        reservePT = ZirconLibrary.calculatePTU(isAnchor, pylonReserve, _totalSupply, translateToPylon(uint(reserve), 0), pylonReserve, _gamma, _vab);
        amount = ZirconLibrary.calculatePTUToAmount(isAnchor, Math.min(reservePT, _liquidity), _totalSupply,translateToPylon(reserve, 0) , pylonReserve, _gamma, _vab);
    }

    // Burn send liquidity back to user burning Pool tokens
    // The function first uses the reserves of the Pylon
    // If not enough reserves it burns The Pool Tokens of the pylon
    function burn(address _to, bool _isAnchor) external lock returns (uint amount){
        sync();
        // Selecting the Pool Token class on basis of the requested tranch to burn
        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
        // Let's get how much liquidity was sent to burn
        //Outside of scope to be used for vab/vfb adjustment later
        uint liquidity = pt.balanceOf(address(this));
        ////console.log("Viva la vida", liquidity);
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY");
        uint initialPT = pt.totalSupply();
        {
            uint _totalSupply = pt.totalSupply();
            address to = _to;
            bool isAnchor = _isAnchor;
            PylonToken memory _pylonToken = pylonToken;
            address _pairAddress = pairAddress;



            // Here we calculate max PTU to extract sync reserve + amount in reserves
            (uint reservePT, uint _amount) = preBurn(isAnchor, _totalSupply, liquidity);
            _safeTransfer(isAnchor ? _pylonToken.anchor : _pylonToken.float, to, _amount);

            ////console.log("burn: reservePT, reserveAmount: ", reservePT, _amount);

            amount = _amount;
            ////console.log("preburnamount", amount);

            ////console.log("<<<<omegaMulDecimals", omegaMulDecimals);
            ////console.log("burn: total vfb: ", virtualFloatBalance);

            if (reservePT < liquidity) {

                uint omegaMulDecimals = 1e18;

                if (isAnchor) {
                    (, uint reserveAnchor,) = getSyncReserves();
                    (, uint pairReserves1)  = getPairReservesNormalized();

                    //Omega is the slashing factor. It's always equal to 1 if pool has gamma above 50%
                    //If it's below 50%, it begins to go below 1 and thus slash any withdrawal.
                    //Note that in practice this system doesn't activate unless the syncReserves are empty.
                    //Also note that a dump of 60% only generates about 10% of slashing.

                    omegaMulDecimals = ZirconLibrary.slashLiabilityOmega(
                        translateToPylon(pairReserves1.mul(2), 0),
                        reserveAnchor,
                        gammaMulDecimals,
                        virtualAnchorBalance);
                }

                uint adjustedLiquidity = ((liquidity.sub(reservePT)).mul(omegaMulDecimals))/1e18;
                ////console.log("adjustedLiquidity", adjustedLiquidity);
                _safeTransfer(_pairAddress, _pairAddress, calculateLPTU(isAnchor, adjustedLiquidity, _totalSupply));
                amount += IZirconPair(_pairAddress).burnOneSide(to, isFloatReserve0 ? !isAnchor : isAnchor);  // XOR
                //Bool combines choice of anchor or float with which token is which in the pool
            }

            pt.burn(address(this), liquidity); //Should burn unadjusted amount ofc
            ////console.log("<<<<liquidity", liquidity);
        }
        //console.log("burn: Final amount", amount);

        if(_isAnchor) {
            virtualAnchorBalance -= virtualAnchorBalance.mul(liquidity)/initialPT;
        }else{
            virtualFloatBalance -= virtualFloatBalance.mul(liquidity)/initialPT;
        }
        //console.log("<<<<extract end\n\n");

        _updateVariables();
        {
            PylonToken memory _pylonTokens = pylonToken;

            uint balance0 = IERC20Uniswap(_pylonTokens.float).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(_pylonTokens.anchor).balanceOf(address(this));

            (uint _pairReserve0, uint _pairReserve1) = getPairReservesNormalized();

            uint112 max0 = _pairReserve0 == 0 ? uint112(balance0.mul(maximumPercentageSync)/100) : uint112(translateToPylon(_pairReserve0, balance0).mul(maximumPercentageSync)/100);
            uint112 max1 = _pairReserve1 == 0 ? uint112(balance1.mul(maximumPercentageSync)/100) : uint112(translateToPylon(_pairReserve1, balance1).mul(maximumPercentageSync)/100);

            updateReservesRemovingExcess(balance0, balance1, max0, max1);
        }

        emit Burn(msg.sender, amount);
    }



    //Works similarly to burn but sends token 50/50
//    function burnAsync(address _to, bool _isAnchor) external lock returns (uint amount0, uint amount1){
//        sync();
//        // Selecting the Pool Token class on basis of the requested tranch to burn
//        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
//        // Let's get how much liquidity was sent to burn
//        //Outside of scope to be used for vab/vfb adjustment later
//        uint liquidity = pt.balanceOf(address(this));
//        //console.log("Viva la vida", liquidity);
//        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY");
//
//        uint _totalSupply = pt.totalSupply();
//        {
//            //uint _totalSupply = pt.totalSupply();
//            address to = _to;
//            bool isAnchor = _isAnchor;
//            PylonToken memory _pylonToken = pylonToken;
//            address _pairAddress = pairAddress;
//
//
//
//
//            // Here we calculate max PTU to extract sync reserve + amount in reserves
//            (uint reservePT, uint _amount0, uint _amount1) = preBurn(isAnchor, false, _totalSupply, liquidity);
//            //console.log("preburnamount", _amount0, _amount1);
//
//            {(uint sync0, uint sync1,) = getSyncReserves();
//                //console.log("syncReserves: ", sync0, sync1);}
//            _safeTransfer(_pylonToken.float, to, _amount0);
//            _safeTransfer(_pylonToken.anchor, to, _amount1);
//
//            ////console.log("burn: reservePT, reserveAmount: ", reservePT, _amount);
//
//
//
//            ////console.log("<<<<omegaMulDecimals", omegaMulDecimals);
//            //console.log("burn: total vfb: ", virtualFloatBalance);
//
//            if (reservePT < liquidity) {
//
//                uint omegaMulDecimals = 1e18;
//
//                if (isAnchor) {
//                    (, uint reserveAnchor,) = getSyncReserves();
//                    (, uint pairReserves1)  = getPairReservesNormalized();
//
//                    //Omega is the slashing factor. It's always equal to 1 if pool has gamma above 50%
//                    //If it's below 50%, it begins to go below 1 and thus slash any withdrawal.
//                    //Note that in practice this system doesn't activate unless the syncReserves are empty.
//                    //Also note that a dump of 60% only generates about 10% of slashing.
//
//                    omegaMulDecimals = ZirconLibrary.slashLiabilityOmega(
//                        translateToPylon(pairReserves1.mul(2), 0),
//                        reserveAnchor,
//                        gammaMulDecimals,
//                        virtualAnchorBalance);
//                }
//
//
//                uint adjustedLiquidity = ((liquidity.sub(reservePT)).mul(omegaMulDecimals))/1e18;
//                //console.log("adjustedLiquidity", adjustedLiquidity);
//                //console.log("burnAsync lptu & uni pt total supply", calculateLPTU(isAnchor, adjustedLiquidity, _totalSupply), IZirconPair(_pairAddress).totalSupply());
//                _safeTransfer(_pairAddress, _pairAddress, calculateLPTU(isAnchor, adjustedLiquidity, _totalSupply));
//                (amount0, amount1) = IZirconPair(_pairAddress).burn(to);
//
//                //Bool combines choice of anchor or float with which token is which in the pool
//            }
//
//            amount0 += _amount0;
//            amount1 += _amount1;
//
//            pt.burn(address(this), liquidity); //Should burn unadjusted amount ofc
//            //console.log("<<<<liquidity", liquidity);
//        }
//        ////console.log("burn: Final amount", amount);
//
//        if(_isAnchor) {
//            virtualAnchorBalance -= virtualAnchorBalance.mul(liquidity)/_totalSupply;
//        }else{
//            virtualFloatBalance -= virtualFloatBalance.mul(liquidity)/_totalSupply;
//        }
//        //console.log("<<<<extract end\n\n");
//
//        //TODO: This should probably be sync not update
//        _updateVariables();
//        emit BurnAsync(msg.sender, amount0, amount1);
//    }
}
