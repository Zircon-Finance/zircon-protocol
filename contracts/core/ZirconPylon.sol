pragma solidity ^0.5.16;
import './libraries/Math.sol';
import './interfaces/IZirconPair.sol';
import './interfaces/IZirconPoolToken.sol';
import "./libraries/SafeMath.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/ZirconLibrary.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IZirconPylonFactory.sol";
import "hardhat/console.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

contract ZirconPylon {
    // **** Libraries ****
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    // **** STRUCTS *****
    struct PylonToken {
        address float;
        address anchor;
    }
    PylonToken public pylonToken;

    // ***** GLOBAL VARIABLES ******

    // ***** The address of the other components ******
    address public pairAddress;
    address public factoryAddress;
    address public pairFactoryAddress;
    address public floatPoolTokenAddress;
    address public anchorPoolTokenAddress;

    // Indicates if in the pair the token0 is float or anchor
    bool public isFloatReserve0;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    // ***** Variables for calculations *****
    uint public virtualAnchorBalance;
    uint public virtualFloatBalance;
    uint public maximumPercentageSync;
    uint public dynamicFeePercentage;
    uint public gammaMulDecimals; // Name represents the fact that this is always the numerator of a fraction with 10**18 as denominator.
    uint public lastK;
    uint public lastPoolTokens;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves (always anchor)
    uint112 private reserve1;           // us es single storage slot, accessible via getReserves (always float)
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    // global variable used for testing
    uint private testMultiplier = 1e16;

    // **** MODIFIERS *****
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'ZP: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    uint public initialized = 0;
    modifier isInitialized() {
        require(initialized == 1, 'ZP: NOT INITIALIZED');
        _;
    }

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

    // **** EVENTS ****
    event PylonUpdate(uint _reserve0, uint _reserve1);
    event PylonSync(uint _vab, uint _vfb, uint _gamma);

    // Transform in just one event
    event MintSync(address sender, uint aIn0, bool isAnchor);
    event MintAsync(address sender, uint aIn0, uint aIn1);
    event MintAsync100(address sender, uint aIn0, bool isAnchor);
    event Burn(address sender, uint aIn0, bool isAnchor);
    event BurnAsync(address sender, uint aIn0, uint aIn1);
    event Excess(uint aIn0, bool isAnchor);

    // ****** CONSTRUCTOR ******
    constructor() public {
        factoryAddress = msg.sender;
    }

    // ****** HELPER FUNCTIONS *****
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Zircon Pylon: TRANSFER_FAILED');
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

    //Function that returns correctly
    // Float -> reserve0
    // Anchor -> reserve1
    function getPairReservesTranslated(uint error0, uint error1)  private view returns  (uint _reserve0, uint _reserve1) {
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        _reserve0 = translateToPylon(uint(_reservePair0), error0);
        _reserve1 = translateToPylon(uint(_reservePair1), error1);
    }

    // Function to obtain Pair Reserves on Pylon Basis
    // In case PTT Or PTB are null it will @return errorReturn
    function translateToPylon(uint toConvert, uint errorReturn) view private returns (uint amount){
        uint ptb = IZirconPair(pairAddress).balanceOf(address(this));
        uint ptt = IZirconPair(pairAddress).totalSupply();
        amount =  (ptt == 0 || ptb == 0) ? errorReturn : toConvert.mul(ptb)/ptt;
    }


    //Helper function to calculate slippage-adjusted share of pool
    function _disincorporateAmount(uint _amountIn, bool isAnchor) private returns (uint amount0, uint amount1) {
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        amount0 = !isAnchor ? _amountIn/2 : ZirconLibrary.getAmountOut(_amountIn/2, _reservePair1, _reservePair0);
        amount1 = isAnchor ? _amountIn/2 : ZirconLibrary.getAmountOut(_amountIn/2, _reservePair0, _reservePair1);
    }

    function getLiquidityFromPoolTokens(uint amountIn0, uint amountIn1,  bool shouldMintAnchor, IZirconPoolToken pt) private returns (uint liquidity, uint amountInAdjusted){
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();
        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves(); // gas savings

        if (shouldMintAnchor) {
            amountInAdjusted = Math.min((amountIn0.mul(_pairReserve1).mul(2))/_pairReserve0, amountIn1.mul(2)); //Adjust AmountIn0 to its value in Anchor tokens
            liquidity = ZirconLibrary.calculatePTU(shouldMintAnchor, amountInAdjusted, pt.totalSupply(), translateToPylon(_pairReserve1, 0), _reserve1, gammaMulDecimals, virtualAnchorBalance);
        }else{
            amountInAdjusted = Math.min((amountIn1.mul(_pairReserve0).mul(2))/_pairReserve1, amountIn0.mul(2)); //Adjust AmountIn1 to its value in Float tokens
            liquidity = ZirconLibrary.calculatePTU(shouldMintAnchor, amountInAdjusted, pt.totalSupply(), translateToPylon(_pairReserve0, 0), _reserve0, gammaMulDecimals, virtualAnchorBalance);
        }
    }

    // ***** INIT ******

    // Called once by the factory at time of deployment
    // @_floatPoolTokenAddress -> Contains Address Of Float PT
    // @_anchorPoolTokenAddress -> Contains Address Of Anchor PT
    // @floatToken -> Float token
    // @anchorToken -> Anchor token
    function initialize(address _floatPoolTokenAddress, address _anchorPoolTokenAddress, address _floatToken, address _anchorToken, address _pairAddress, address _pairFactoryAddress) external lock {
        require(msg.sender == factoryAddress, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolTokenAddress = _floatPoolTokenAddress;
        anchorPoolTokenAddress = _anchorPoolTokenAddress;
        pairAddress = _pairAddress;
        isFloatReserve0 = IZirconPair(_pairAddress).token0() == _floatToken;
        pylonToken = PylonToken(_floatToken, _anchorToken);
        pairFactoryAddress = _pairFactoryAddress;

        maximumPercentageSync = IZirconPylonFactory(factoryAddress).maximumPercentageSync();
        dynamicFeePercentage = IZirconPylonFactory(factoryAddress).dynamicFeePercentage();
    }

    // On init pylon we have to handle two cases
    // The first case is when we initialize the pair through the pylon
    // And the second one is when initialize the pylon with a pair already existing
    function initPylon(address _to) external lock returns (uint floatLiquidity, uint anchorLiquidity) {
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
        if (_reservePair0 > 0 && _reservePair1 > 0) {
            uint denominator = (virtualAnchorBalance.mul(_reservePair0))/_reservePair1;
            gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));
            //This is gamma formula when FTV <= 50%
        } else {
            // When Pair is not initialized let's start gamma to 0.5
            gammaMulDecimals = 500000000000000000;
        }
        //TODO: Old definition of gamma, necessary because pool may not be initialized but check for weird interactions
        // Time to mint some tokens
        anchorLiquidity = _mintPoolToken(balance1, 0, _reservePair1, anchorPoolTokenAddress, _to, true);
        floatLiquidity = _mintPoolToken(balance0, 0, _reservePair0, floatPoolTokenAddress, _to, false);

        //Here it updates the state and throws liquidity into the pool if possible
        _update();
        initialized = 1;
    }


    // ***** EXCESS RESERVES ******


    // This function takes
    // @balance0 & @balance1 -> The New Balances After A Sync Update
    // @max0 & @max1 -> The maximum that we can save on the reserves
    // If we have any excess reserves we donate them to the pool
    // Todo: Function should be fine although the mintOneSide usage could be dangerous
    // Todo: But we need to check how we use it.
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



    // ****** UPDATE ********

    // Update reserves and, on the first call per block, price accumulator
    // Any excess of balance is going to be donated to the pair
    // So... here we get the maximum off both tokens and we mint Pool Tokens

    //Sends pylonReserves to pool if there is a match
    function _update() private {
        // Let's take the current balances
        uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));

        // Intializing the variables, (Maybe gas consuming let's see how to sort out this
        // Getting pair reserves and updating variables before minting
        // Max0 and Max1 are two variables representing the maximum that can be minted on sync
        // Min0/2 & Min1/2 remain as reserves on the pylon
        // In the case the pair hasn't been initialized pair reserves will be 0 so we take our current balance as the maximum
        (uint reservesTranslated0, uint reservesTranslated1) = getPairReservesTranslated(balance0, balance1);

        uint112 max0 = uint112(reservesTranslated0.mul(maximumPercentageSync)/100);
        uint112 max1 = uint112(reservesTranslated1.mul(maximumPercentageSync)/100);
        // Pylon Update Minting
        if (balance0 > max0/2 && balance1 > max1/2) {
            // Get Maximum simple gets the maximum quantity of token that we can mint
            (uint px, uint py) = ZirconLibrary._getMaximum(
                reservesTranslated0,
                reservesTranslated1,
                balance0.sub(max0/2), balance1.sub(max1/2));
            // Transferring tokens to pair and minting
            if(px != 0) _safeTransfer(pylonToken.float, pairAddress, px);
            if(py != 0) _safeTransfer(pylonToken.anchor, pairAddress, py);
            IZirconPair(pairAddress).mint(address(this));
            // Removing tokens sent to the pair to balances
            balance0 -= px;
            balance1 -= py;
        }

        // Let's remove the tokens that are above max0 and max1, and donate them to the pool
        // This is for cases where somebody just donates tokens to pylon; tx reverts if this done via core functions
        //Todo: This is likely also invoked if the price dumps and the sync pool is suddenly above max, not ideal behavior...

        updateReservesRemovingExcess(balance0, balance1, max0, max1);
        _updateVariables();

        // Updating Variables
    }
    // This Function is called to update some variables needed for calculation
    // TODO: This seems wrong, updating these variables without syncing would essentially skip a key state transition.
    // TODO: Likely that we need to replace all uses of this with sync()
    function _updateVariables() private {
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();
        lastPoolTokens = IZirconPair(pairAddress).totalSupply();
        lastK = uint(_pairReserve0).mul(_pairReserve1);

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        blockTimestampLast = blockTimestamp;
    }

    // *** MINT FEE ****
    // @amount and @poolToken
    function _mintFee(uint amount, address poolToken) private returns (bool minted){
        address feeTo = IUniswapV2Factory(pairFactoryAddress).feeTo();
        minted = feeTo != address(0);
        if (minted) {
            IZirconPoolToken(poolToken).mint(feeTo, amount);
        }
    }


    // ***** MINTING *****

    // Mint Pool Token
    // @_balance -> Balance OF PT
    // @_pylonReserve -> Reserves of PT on Pylon
    function _mintPoolToken(uint amountIn, uint _pylonReserve, uint _pairReserveTranslated,
        address _poolTokenAddress, address _to,  bool isAnchor) private returns (uint liquidity) {

        require(amountIn > 0, "ZP: Not Enough Liquidity");
        uint pts = IZirconPoolToken(_poolTokenAddress).totalSupply();
        {
            uint _gamma = gammaMulDecimals;
            uint _vab = virtualAnchorBalance;

            if (pts == 0) {
                IZirconPoolToken(_poolTokenAddress).mint(address(0), MINIMUM_LIQUIDITY);
                if (isAnchor) {
                    liquidity = amountIn.sub(MINIMUM_LIQUIDITY);
                }else{
                    liquidity = (amountIn.mul(1e18)/_gamma.mul(2)).sub(MINIMUM_LIQUIDITY);
                }
            }else{
                liquidity = ZirconLibrary.calculatePTU(isAnchor, amountIn, pts, _pairReserveTranslated, _pylonReserve, _gamma, _vab);
            }
        }
        uint fee = liquidity.mul(dynamicFeePercentage)/100;
        if(_mintFee(fee, _poolTokenAddress)) {
            liquidity -= fee;
        }
        IZirconPoolToken(_poolTokenAddress).mint(_to, liquidity);
        emit MintSync(msg.sender, amountIn, isAnchor);
    }

    // External Function called to mint pool Token
    // Liquidity have to be sent before
    // TODO: recheck in dump scenario if sync pool can be blocked

    // aka syncMint
    function mintPoolTokens(address _to, bool isAnchor) isInitialized lock external returns (uint liquidity) {

        sync();

        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves();
        (uint _reservePairTranslated0, uint _reservePairTranslated1) = getPairReservesTranslated(0, 0);
        uint amountIn;
        // Minting Pool tokens
        if (isAnchor) {
            uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
            amountIn = balance1.sub(_reserve1);
            liquidity = _mintPoolToken(amountIn, _reserve1, _reservePairTranslated1, anchorPoolTokenAddress, _to, isAnchor);
        } else {
            uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            amountIn = balance0.sub(_reserve0);
            liquidity = _mintPoolToken(amountIn, _reserve0, _reservePairTranslated0, floatPoolTokenAddress, _to, isAnchor);
        }
        // Updating VAB & VFB
        if(isAnchor) {
            virtualAnchorBalance += amountIn;
        }else{
            virtualFloatBalance += amountIn;
        }
        //Sends tokens into pool if there is a match
        _update();

    }

    function mintAsync100(address to, bool isAnchor) lock isInitialized external returns (uint liquidity) {
        sync();

        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves();
        uint amountIn;
        if (isAnchor) {
            uint balance = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));
            amountIn = balance.sub(_reserve1);
        }else{
            uint balance = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            amountIn = balance.sub(_reserve0);
        }
        require(amountIn > 0, "ZP: INSUFFICIENT_AMOUNT");
        _safeTransfer(isAnchor ? pylonToken.anchor : pylonToken.float, pairAddress, amountIn);
        {
            (uint a0, uint a1) = _disincorporateAmount(amountIn, isAnchor);

            (uint _liquidity, uint amount) = getLiquidityFromPoolTokens(
                a0, a1,
                isAnchor,
                IZirconPoolToken(isAnchor ? anchorPoolTokenAddress : floatPoolTokenAddress));

            liquidity = _liquidity;
            if (isAnchor) {
                virtualAnchorBalance += amount;
            }else{
                virtualFloatBalance += amount;
            }

            (uint liq,,) = IZirconPair(pairAddress).mintOneSide(address(this), isFloatReserve0 ? !isAnchor : isAnchor);
            IZirconPoolToken(isAnchor ? anchorPoolTokenAddress : floatPoolTokenAddress).mint(to, liquidity);
        }

        _updateVariables();
        emit MintAsync100(msg.sender, amountIn, isAnchor);
    }



    //TODO: Transfer first then calculate on basis of pool token share how many share we should give to the user
    function mintAsync(address to, bool shouldMintAnchor) external lock isInitialized returns (uint liquidity){
        sync();
        address feeTo = IUniswapV2Factory(pairFactoryAddress).feeTo();
        address _poolTokenAddress = shouldMintAnchor ? anchorPoolTokenAddress : floatPoolTokenAddress;

        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves(); // gas savings
        uint amountIn0;
        uint amountIn1;
        {
            uint balance0 = IERC20Uniswap(pylonToken.float).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(pylonToken.anchor).balanceOf(address(this));

            amountIn0 = balance0.sub(_reserve0);
            amountIn1 = balance1.sub(_reserve1);

            (uint _liquidity, uint amount) = getLiquidityFromPoolTokens(amountIn0, amountIn1, shouldMintAnchor, IZirconPoolToken(_poolTokenAddress));
            liquidity = _liquidity;
            if (shouldMintAnchor) {
                virtualAnchorBalance += amount;
            } else {
                virtualFloatBalance += amount;
            }

        }

        require(amountIn1 > 0 && amountIn0 > 0, "ZirconPylon: Not Enough Liquidity");
        _safeTransfer(pylonToken.float, pairAddress, amountIn0);
        _safeTransfer(pylonToken.anchor, pairAddress, amountIn1);
        (uint l) = IZirconPair(pairAddress).mint(address(this));
        // uint deltaSupply = pair.totalSupply().sub(_totalSupply);
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
        if (lastPoolTokens != 0 && pairReserve0 != 0 && pairReserve1 != 0) {

            uint poolTokensPrime = IZirconPair(pairAddress).totalSupply();
            // Here it is going to be useful to have a Minimum Liquidity
            // If not we can have some problems
            // uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this));
            // Let's get the amount of total pool value own by pylon

            //TODO: Add system that accumulates fees to cover insolvent withdrawals (and thus changes ptb)
            //TODO: Add impact of Anchor/Float pts

            uint totalPoolValueAnchorPrime = translateToPylon(pairReserve1.mul(2), 0);
            uint totalPoolValueFloatPrime = translateToPylon(pairReserve0.mul(2), 0);

            uint one = 1e18;
            uint d = (one).sub((Math.sqrt(lastK)*poolTokensPrime*1e18)/(Math.sqrt(currentK)*lastPoolTokens));

            // Getting how much fee value has been created for pylon
            uint feeValueAnchor = totalPoolValueAnchorPrime.mul(d)/1e18;
            uint feeValueFloat = totalPoolValueFloatPrime.mul(d)/1e18;
            console.log("sync::anchor::fee", feeValueAnchor);
            console.log("sync::float::fee", feeValueFloat);

            // Calculating gamma, variable used to calculate tokens to mint and withdrawals

            // gamma is supposed to always be an accurate reflection of the float share as a percentage of the totalPoolValue
            // however vfb also includes the syncPool reserve portion, which is completely outside of the pools.
            // Nonetheless, the syncPool is still considered part of the user base/float share.
            // This is relevant primarily for fee calculations, but that's already a given: you just use the same proportions.
            // In all other places we (should) already account for the sync pool separately.

            // When operating on fractional, gamma is higher than it should be compared to ftv + atv.
            // This means that anchors get more fees than they "should", which kinda works out because they're at high risk.
            // It works as an additional incentive to not withdraw.

            virtualAnchorBalance += ((feeValueAnchor.mul(1e18-gammaMulDecimals))/1e18);
            virtualFloatBalance += ((gammaMulDecimals).mul(feeValueFloat)/1e18);

            if ((virtualAnchorBalance.sub(pylonReserve1)) < totalPoolValueAnchorPrime/2) {
                gammaMulDecimals = 1e18 - ((virtualAnchorBalance.sub(pylonReserve1))*1e18 /  totalPoolValueAnchorPrime);
            } else {
                //TODO: Check that this works and there are no gamma that assume gamma is ftv/atv+ftv
                gammaMulDecimals = ((virtualFloatBalance.sub(pylonReserve0)) *1e18) /  totalPoolValueFloatPrime;
            }



            // TODO: (see if make sense to insert a floor to for example 25/75)
            //Sync pool also gets a claim to these
            emit PylonSync(virtualAnchorBalance, virtualFloatBalance, gammaMulDecimals);
        }
    }

    function calculateLPTU(bool _isAnchor, uint _liquidity, uint _ptTotalSupply) view private returns (uint claim){
        (uint _reserve0, uint _reserve1) = getPairReservesTranslated(1, 1); // gas savings
        (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getSyncReserves(); // gas savings
        uint pylonShare;
        if (_isAnchor) {
            pylonShare = (IZirconPair(pairAddress).balanceOf(address(this)).mul(virtualAnchorBalance.sub(_pylonReserve1)))/_reserve1.mul(2);
            //Adjustment factor to extract correct amount of liquidity
            pylonShare = pylonShare.add(pylonShare.mul(_pylonReserve1)/_reserve1.mul(2));
        }else{
            pylonShare = ((gammaMulDecimals).mul(IZirconPair(pairAddress).balanceOf(address(this))))/1e18;
            pylonShare = pylonShare.add(pylonShare.mul(_pylonReserve0)/_reserve0.mul(2));
        }
        //Liquidity/pt applies share over pool + reserves to something that is just pool. So it gives less liquidity than it should
        claim = (_liquidity.mul(pylonShare))/_ptTotalSupply;
        require(claim > 0, 'ZP: INSUFFICIENT_LIQUIDITY_BURNED');
    }

    // Burn Async send both tokens 50-50
    // Liquidity has to be sent before
    //Old
    function burnAsync(address _to, bool _isAnchor) external lock isInitialized returns (uint amount0, uint amount1){
        sync();

        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolTokenAddress : floatPoolTokenAddress);
        uint liquidity = pt.balanceOf(address(this));
        require(liquidity > 0, "ZP: Not enough liquidity inserted");
        uint ptTotalSupply = pt.totalSupply();
        uint omegaMulDecimals = 1e18;
        {
            (uint reserveFloat, uint reserveAnchor,) = getSyncReserves();
            (uint pairReserves0, uint pairReserves1) = getPairReservesTranslated(0, 0);
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
                omegaMulDecimals = ZirconLibrary.slashLiabilityOmega(
                    pairReserves1.mul(2),
                    reserveAnchor,
                    gammaMulDecimals,
                    virtualAnchorBalance);
            }
        }
        uint adjustedLiquidity = liquidity.mul(omegaMulDecimals)/1e18;
        uint ptu = calculateLPTU(_isAnchor, adjustedLiquidity, ptTotalSupply);
        _safeTransfer(pairAddress, pairAddress, ptu);

        (uint amountA, uint amountB) = IZirconPair(pairAddress).burn(_to);
        amount0 = isFloatReserve0 ? amountA : amountB;
        amount1 = isFloatReserve0 ? amountB : amountA;


        if(_isAnchor) {
            virtualAnchorBalance -= virtualAnchorBalance.mul(liquidity)/ptTotalSupply;
        } else {
            virtualFloatBalance -= virtualFloatBalance.mul(liquidity)/ptTotalSupply;
        }
        //Burns the Zircon pool tokens
        pt.burn(address(this), liquidity);
        _update();

        emit BurnAsync(msg.sender, amount0, amount1);

    }

    // Function That calculates the amount of reserves in PTU
    // and the amount of the minimum from liquidity and reserves
    // Helper function for burn
    function preBurn(bool isAnchor, uint _totalSupply, uint _liquidity) view private returns (uint reservePT, uint amount) {
        // variables declaration
        uint _gamma = gammaMulDecimals;
        uint _vab = virtualAnchorBalance;
        (uint _reserve0, uint _reserve1) = getPairReservesTranslated(0,0); // gas savings
        (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getSyncReserves();

        //Calculates maxPTs that can be serviced through Pylon Reserves
        uint pylonReserve = isAnchor ? _pylonReserve1 : _pylonReserve0;
        uint reserve = isAnchor ? reserve1 : _reserve0;
        reservePT = ZirconLibrary.calculatePTU(isAnchor, pylonReserve, _totalSupply, reserve, pylonReserve, _gamma, _vab);
        amount = ZirconLibrary.calculatePTUToAmount(isAnchor, Math.min(reservePT, _liquidity), _totalSupply,reserve, pylonReserve, _gamma, _vab);
    }

    // Burn send liquidity back to user burning Pool tokens
    // The function first uses the reserves of the Pylon
    // If not enough reserves it burns The Pool Tokens of the pylon
    function burn(address _to, bool _isAnchor) external lock isInitialized returns (uint amount){
        sync();
        // Selecting the Pool Token class on basis of the requested tranch to burn
        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolTokenAddress : floatPoolTokenAddress);
        // Let's get how much liquidity was sent to burn
        // Outside of scope to be used for vab/vfb adjustment later
        uint liquidity = pt.balanceOf(address(this));
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY");
        uint _totalSupply = pt.totalSupply();
        {
            address to = _to;
            bool isAnchor = _isAnchor;
            address _pairAddress = pairAddress;

            // Here we calculate max PTU to extract sync reserve + amount in reserves
            (uint reservePT, uint _amount) = preBurn(isAnchor, _totalSupply, liquidity);
            _safeTransfer(isAnchor ? pylonToken.anchor : pylonToken.float, to, _amount);
            amount = _amount;

            if (reservePT < liquidity) {
                uint omegaMulDecimals = 1e18;
                if (isAnchor) {
                    (, uint reserveAnchor,) = getSyncReserves();
                    (, uint pairReserves1)  = getPairReservesTranslated(0,0);
                    //Omega is the slashing factor. It's always equal to 1 if pool has gamma above 50%
                    //If it's below 50%, it begins to go below 1 and thus slash any withdrawal.
                    //Note that in practice this system doesn't activate unless the syncReserves are empty.
                    //Also note that a dump of 60% only generates about 10% of slashing.
                    omegaMulDecimals = ZirconLibrary.slashLiabilityOmega(
                        pairReserves1.mul(2),
                        reserveAnchor,
                        gammaMulDecimals,
                        virtualAnchorBalance);
                }

                uint adjustedLiquidity = ((liquidity.sub(reservePT)).mul(omegaMulDecimals))/1e18;
                _safeTransfer(_pairAddress, _pairAddress, calculateLPTU(isAnchor, adjustedLiquidity, _totalSupply));
                amount += IZirconPair(_pairAddress).burnOneSide(to, isFloatReserve0 ? !isAnchor : isAnchor);  // XOR
                //Bool combines choice of anchor or float with which token is which in the pool
            }
            pt.burn(address(this), liquidity); //Should burn unadjusted amount ofc
        }

        if(_isAnchor) {
            virtualAnchorBalance -= virtualAnchorBalance.mul(liquidity)/_totalSupply;
        }else{
            virtualFloatBalance -= virtualFloatBalance.mul(liquidity)/_totalSupply;
        }

        _update();
        emit Burn(msg.sender, amount, _isAnchor);
    }
}
