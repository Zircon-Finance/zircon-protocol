pragma solidity ^0.5.16;
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './libraries/Math.sol';
import './interfaces/IZirconPair.sol';
import './interfaces/IZirconPoolToken.sol';
import "./libraries/SafeMath.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "./ZirconPylonFactory.sol";
import "./libraries/ZirconLibrary.sol";
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';
import "hardhat/console.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

contract ZirconPylon {
    using SafeMath for uint112;
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    struct Pair {
        address token0;
        address token1;
    }
    bool public isFloatReserve0;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    address public pairAddress;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public pairFactory;
    address public floatPoolToken;
    address public anchorPoolToken;

    Pair public pair;

    uint public maxFloatSync;
    uint public maxAnchorSync;

    uint public virtualAnchorBalance; // TODO: make private
    uint public virtualFloatBalance; // TODO: make private
    uint public maximumPercentageSync; //TODO: Error calculating this in the code should be x*maxPercentageSync/100
    uint public dynamicFeePercentage;

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
        dynamicFeePercentage = 5;
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
    // @token0 -> Float token
    // @token1 -> Anchor token
    function initialize(address _floatPoolToken, address _anchorPoolToken, address _token0, address _token1, address _pairAddress, address _pairFactory) external {
        require(msg.sender == factory, 'Zircon: FORBIDDEN'); // sufficient check
        floatPoolToken = _floatPoolToken;
        anchorPoolToken = _anchorPoolToken;
        pairAddress = _pairAddress;
        isFloatReserve0 = IZirconPair(_pairAddress).token0() == _token0;
        // In Pair we save token0 and token1
        //By definition token0 is Float and token1 is Anchor
        pair = Pair(_token0, _token1);
        pairFactory = _pairFactory;
        // Retrieving maximum sync from ZPF
        maxFloatSync = ZirconPylonFactory(factory).maxFloat();
        maxAnchorSync = ZirconPylonFactory(factory).maxAnchor();
    }

    // TODO: mint AT and FT minus a minimum liquidity in PT
    // TODO: this shit has to be 50-50
    // On init pylon we have to handle two cases
    // The first case is when we initialize the pair through the pylon
    // And the second one is when initialize the pylon with a pair already existing
    function initPylon(address _to) external lock{
        console.log("<<<Pylon:_initPylon:::: ");
        require(initialized == 0, "Already Initialized");

        // Let's get the balances so we can see what the user send us
        // As we are initializing the reserves are going to be null

        uint balance0 = IERC20Uniswap(pair.token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(pair.token1).balanceOf(address(this));
        require(balance0 > 0 && balance1 > 0, "ZP: Not enough liquidity");

        console.log("<<<Pylon:initPylon::::balance0=", balance0, ":::balance1", balance1);

        // Let's see if the pair contains some reserves
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();
        console.log("<<<Pylon:initPylon::::_reservePair0=", _reservePair0, ":::_reservePair1", _reservePair1);
        // If pair contains reserves we have to use the ratio of the Pair so...
        if (_reservePair0 > 0 && _reservePair1 > 0) {
            // Getting maximum to initialize the VFB and VAB variables
            // (uint maxX, uint maxY) = ZirconLibrary._getMaximum(_reservePair0, _reservePair1, balance0, balance1);

            // Todo: Check Potential edge case when users supply imbalanced tokens
            virtualFloatBalance = balance0;
            virtualAnchorBalance = balance1;
            //            console.log("<<<Pylon:initPylon::::maxX=", maxX, ":::maxY", maxY);
            uint denominator = (virtualAnchorBalance.mul(_reservePair0))/_reservePair1;
            //This is gamma formula when FTV <= 50%
            gammaMulDecimals = (virtualFloatBalance*1e18) /  (virtualFloatBalance.add(denominator));
        }else {
            // Here we initialize the variables of the sync
            virtualFloatBalance = balance0;
            virtualAnchorBalance = balance1;

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

        //Here it updates the state and throws liquidity into the pool if possible
        _update();
        initialized = 1;
    }


    // This function takes
    // @balance0 & @balance1 -> The New Balances After A Sync Update
    // @max0 & @max1 -> The maximum that we can save on the reserves
    // If we have any excess reserves we donate them to the pool

    //TODO: Function is sensitive, check if it can't be abused
    function updateReservesRemovingExcess(uint balance0, uint balance1, uint112 max0, uint112 max1) private {
        uint112 newReserve0 = uint112(balance0);
        uint112 newReserve1 = uint112(balance1);
        console.log("<<<Pylon:newReserve::::::::", newReserve0/testMultiplier, newReserve1/testMultiplier);

        if (max0 < newReserve0) {
            uint112 excessReserves = uint112(newReserve0.sub(max0));
            _safeTransfer(pair.token0, pairAddress, excessReserves);
            reserve0 = max0;
            console.log("<<<Pylon:excessReserves0::::::::", excessReserves/testMultiplier);
        } else {
            reserve0 = newReserve0;
        }
        if (max1 < newReserve1) {
            uint112 excessReserves = uint112(newReserve1.sub(max1));
            _safeTransfer(pair.token1, pairAddress, excessReserves);
            reserve1 = max1;
            console.log("<<<Pylon:excessReserves1::::::::", excessReserves/testMultiplier);
        }else{
            reserve1 = newReserve1;
        }
        console.log("<<<Pylon:new res::::::::", reserve0/testMultiplier, reserve1/testMultiplier);
        emit PylonUpdate(reserve0, reserve1);
    }

    function translateToPylon(bool _isAnchor, uint toConvert) private returns (uint amount){
        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
        uint ptb = pt.balanceOf(address(this));
        uint ptt = pt.totalSupply();
        amount =  toConvert.mul(ptb)/ptt;
    }


    // Update reserves and, on the first call per block, price accumulator
    // Any excess of balance is going to be donated to the pair
    // So... here we get the maximum of both tokens and we mint Pool Tokens
    //TODO: think a way to do only one transfer by token
    function _update() private {
        console.log("<<<Pylon:_update::::::::start");
        // Let's take the current balances
        Pair memory _pair = pair;
        uint balance0 = IERC20Uniswap(_pair.token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(_pair.token1).balanceOf(address(this));

        // Intializing the variables, (Maybe gas consuming let's see how to sort out this
        IZirconPair pair = IZirconPair(pairAddress);
        // Getting peir reserves and updating variables before minting
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();

        // Max0 and Max1 are two variables representing the maximum that can be minted on sync
        // Min0/2 & Min1/2 remains as reserves on the pylon
        // In the case the pair hasn't been initialized pair reserves will be 0 so we take our current balance as the maximum
        uint reservesTranslated = translateToPylon(false, _pairReserve0);

        uint112 max0 = _pairReserve0 == 0 ? uint112(balance0.mul(maximumPercentageSync)/100) : uint112(reservesTranslated.mul(maximumPercentageSync)/100);
        uint112 max1 = _pairReserve1 == 0 ? uint112(balance1.mul(maximumPercentageSync)/100) : uint112(reservesTranslated.mul(maximumPercentageSync)/100);
        console.log("<<<Pylon:balances::::::::", balance0/testMultiplier, balance1/testMultiplier);
        console.log("<<<Pylon:pairReserves::::::::", _pairReserve0/testMultiplier, _pairReserve1/testMultiplier);
        // Pylon Update Minting
        //TODO: check if it is necessary a timeElapsed check
        console.log("<<<Pylon:values::maxes::::::::", max0/testMultiplier, max1/testMultiplier);
        if (balance0 > max0/2 && balance1 > max1/2) {
            console.log("<<<Pylon:values::getMax::::::::", balance0/10**18, balance1/10**18);
            // Get Maximum simple gets the maximum quantity of token that we can mint
            //TODO: Probably we can eliminate this function and calculate this on pairToken basis
            (uint px, uint py) = ZirconLibrary._getMaximum(
                _pairReserve0 == 0 ? balance0 : _pairReserve0,
                _pairReserve1 == 0 ? balance1 :_pairReserve1,
                balance0.sub(max0/2), balance1.sub(max1/2));
            console.log("<<<Pylon:_getMaximum::::::::", px/testMultiplier, py/testMultiplier);

            // Transfering tokens to pair and minting
            if(px != 0) _safeTransfer(_pair.token0, pairAddress, px);
            if(py != 0) _safeTransfer(_pair.token1, pairAddress, py);
            pair.mint(address(this));

            // Removing tokens sent to the pair to balances
            balance0 -= px;
            balance1 -= py;
        }
        // 2022

        // Let's remove the tokens that are above max0 and max1, and donate them to the pool
        // This is for cases where somebody just donates tokens to the pool; tx reverts if this done via core functions

        // TODO: Instead of donating we can use async-100% and create some LP tokens for pair
        updateReservesRemovingExcess(balance0, balance1, max0, max1);
        _updateVariables();

        // Updating Variables
        console.log("<<<Pylon:update::::::::end\n\n");

    }
    // This Function is called to update some variables needed for calculation
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
    function _mintFee(uint amount, address poolToken) private returns (bool feeOn){
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        IZirconPoolToken pt = IZirconPoolToken(poolToken);
        feeOn = feeTo != address(0);
        if (feeOn) {
            pt.mint(feeTo, amount);
        }
    }

    // Mint Pool Token
    // @_balance -> Balance OF PT
    // @_pylonReserve -> Reserves of PT on Pylon
    function _mintPoolToken(uint _balance, uint112 _pylonReserve, uint112 _pairReserve, address _poolTokenAddress, address _to, bool isAnchor) private returns (uint liquidity) {
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        IZirconPoolToken pt = IZirconPoolToken(_poolTokenAddress);
        uint amountIn = _balance.sub(_pylonReserve);
        require(amountIn > 0, "ZP: Not Enough Liquidity");
        {
            // TODO: Clean up this to avoid using hardcoded values
            uint pylonReserve = _pylonReserve;
            uint pairReserve = _pairReserve;
            uint pairReserveTranslated = translateToPylon(isAnchor, pairReserve);
            uint maxSync = (pairReserveTranslated == 0 || _pylonReserve > pairReserveTranslated) ? maxFloatSync :
            (pairReserveTranslated.mul(maximumPercentageSync)/100).sub(_pylonReserve);
            require(maxSync > amountIn, "ZP: Exceeds");
            uint _gamma = gammaMulDecimals;
            uint _vab = virtualAnchorBalance;
            uint pts = pt.totalSupply();

            if(pts != 0){
                // When pts is null we don't update @vab and @vfb because in the init are already updated
                if(isAnchor) {
                    virtualAnchorBalance += amountIn;
                }else{
                    virtualFloatBalance += amountIn;
                }
            }
            // When @pts is null we mint some liquidity to null address to ensure pt is never 0
            if (pts == 0) pt.mint(address(0), MINIMUM_LIQUIDITY);
            liquidity = ZirconLibrary.calculatePTU(isAnchor, amountIn, pts, pairReserve, pylonReserve, _gamma, _vab);
            console.log("<<<Pylon:::::::liquidity>>>> ", liquidity/testMultiplier);
            pt.mint(_to, liquidity);
        }

        uint fee = feeTo != address(0) ? 0 : liquidity.mul(dynamicFeePercentage)/100;
        if (fee != 0) _mintFee(fee, _poolTokenAddress);

        emit MintPT(reserve0, reserve1);
        console.log("<<<Pylon:_mintPoolToken::::::::end \n\n");
    }
    // External Function called to mint pool Token
    // Liquidity have to be sent before
    function mintPoolTokens(address to, bool isAnchor) isInitialized external returns (uint liquidity) {
        sync();
        uint balance0 = IERC20Uniswap(pair.token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(pair.token1).balanceOf(address(this));
        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves();
        (uint112 _reservePair0, uint112 _reservePair1) = getPairReservesNormalized();

        if (isAnchor) {
            liquidity = _mintPoolToken(balance1, _reserve1, _reservePair1, anchorPoolToken, to, isAnchor);
        }else{
            liquidity = _mintPoolToken(balance0, _reserve0, _reservePair0, floatPoolToken, to, isAnchor);
        }
        _update();
    }

    //TODO: Transfer first then calculate on basis of pool token share how many share we should give to the user
    function mintAsync(address to, bool shouldMintAnchor) external lock isInitialized returns (uint liquidity){
        sync();
        address feeTo = IUniswapV2Factory(pairFactory).feeTo();
        address _poolTokenAddress = shouldMintAnchor ? anchorPoolToken : floatPoolToken;
        IZirconPoolToken pt = IZirconPoolToken(_poolTokenAddress);
        Pair memory _pair = pair;
        IZirconPair pairZircon = IZirconPair(pairAddress);
        (uint112 _pairReserve0, uint112 _pairReserve1) = getPairReservesNormalized();

        (uint112 _reserve0, uint112 _reserve1,) = getSyncReserves(); // gas savings
        uint amountIn0;
        uint amountIn1;
        {
            address _token0 = _pair.token0;
            address _token1 = _pair.token1;
            IZirconPair _pairZircon = pairZircon;
            address feeTo = IUniswapV2Factory(pairFactory).feeTo();
            uint balance0 = IERC20Uniswap(_token0).balanceOf(address(this));
            uint balance1 = IERC20Uniswap(_token1).balanceOf(address(this));
            console.log("<<<Pylon:r::::::::", balance0/testMultiplier, reserve0/testMultiplier);
            console.log("<<<Pylon:m::::::::", balance1/testMultiplier, reserve1/testMultiplier);
            amountIn0 = balance0.sub(_reserve0);
            amountIn1 = balance1.sub(_reserve1);
            console.log("<<<Pylon:first::::::::", amountIn0, amountIn1);

            require(amountIn1 > 0 && amountIn0 > 0, "ZirconPylon: Not Enough Liquidity");
            _safeTransfer(_token0, pairAddress, amountIn0);
            _safeTransfer(_token1, pairAddress, amountIn1);
            _pairZircon.mint(address(this));
        }
        //        uint deltaSupply = pair.totalSupply().sub(_totalSupply);
        // TODO: maybe another formula is faster
        // TODO: check maximum to mint
        if (shouldMintAnchor) {
            uint amountInAdjusted = Math.min(amountIn0.mul(_pairReserve1).mul(2)/_pairReserve0, amountIn1.mul(2)); //Adjust AmountIn0 to its value in Anchor tokens
            liquidity = (amountInAdjusted.mul(pt.totalSupply()))/virtualAnchorBalance;
        }else{
            uint amountInAdjusted = Math.min(amountIn1.mul(_pairReserve0).mul(2)/_pairReserve1, amountIn0.mul(2)); //Adjust AmountIn1 to its value in Float tokens
            // TODO: Change def of Gamma everywhere so that it's adjusted when tpv < vab + vfb (i.e the pool operates on fractional reserve)
            liquidity = amountInAdjusted.mul(pt.totalSupply())/(_pairReserve0.mul(2).mul(gammaMulDecimals));
            // Todo: Change toTransfer (probably remove?)
        }
        pt.mint(to, liquidity);
        emit MintPT(reserve1, reserve0);
        console.log("<<<Pylon:liquidity::::::::", liquidity/testMultiplier);

        uint fee = feeTo != address(0) ? 0 : liquidity.mul(dynamicFeePercentage)/100;
        if (fee != 0) _mintFee(fee, _poolTokenAddress);
        console.log("<<<Pylon:mintAsync:::::::: \n\n");

        _updateVariables();
    }
    function sync() public {
        if(msg.sender != pairAddress) { IZirconPair(pairAddress).tryLock(); }
        // So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        // Then it applies the base formula:
        // Adds fees to virtualFloat and virtualAnchor
        // And then calculates Gamma so that the proportions are correct according to the formula
        (uint112 pairReserve0, uint112 pairReserve1) = getPairReservesNormalized();
        // If the current K is equal to the last K, means that we haven't had any updates on the pair level
        // So is useless to update any variable because fees on pair haven't changed
        uint currentK = uint(pairReserve0).mul(pairReserve1);
        console.log("<<<Pylon:sync::::::::currentK'=", currentK/testMultiplier, "::::lastK=", lastK/testMultiplier);
        //  && lastK < currentK
        if (lastPoolTokens != 0 && pairReserve0 != 0 && pairReserve1 != 0) {

            uint poolTokensPrime = IZirconPair(pairAddress).totalSupply();

            // Here it is going to be useful to have a Minimum Liquidity
            // If not we can have some problems
            uint poolTokenBalance = IZirconPair(pairAddress).balanceOf(address(this));
            console.log("<<<Pylon:sync::::::::pt'=", poolTokensPrime/testMultiplier, "::::ptb=", poolTokenBalance/testMultiplier);

            // Let's get the amount of total pool value own by pylon

            //TODO: Add system that accumulates fees to cover insolvent withdrawals (and thus changes ptb)
            uint totalPoolValuePrime = pairReserve1.mul(2).mul(poolTokenBalance)/poolTokensPrime;
            console.log("<<<Pylon:sync::::::::tpv'=", totalPoolValuePrime/testMultiplier);
            console.log("<<<Pylon:sync::::::::r0,r1=", pairReserve0/testMultiplier, pairReserve1/testMultiplier);

            uint rootK = Math.sqrt(currentK);
            uint d = 1e18 - (Math.sqrt(lastK)*poolTokensPrime*1e18)/(rootK*lastPoolTokens);
            console.log("<<<Pylon:sync::::::::lk=", lastK/testMultiplier);
            console.log("<<<Pylon:sync::::::::lpt'=", lastPoolTokens/testMultiplier);
            console.log("<<<Pylon:sync::::::::d=", d);
            // Getting how much fee value has been created for pylon
            uint feeValue = totalPoolValuePrime.mul(d)/1e18;
            console.log("<<<Pylon:sync::::::::fee=", feeValue/testMultiplier);

            // Calculating gamma, variable used to calculate tokens to mint and withdrawals
            console.log("<<<Pylon:sync:::::::prev:vab'=", virtualAnchorBalance/testMultiplier,
                "<<<Pylon:sync::::::::vfb'=", virtualFloatBalance/testMultiplier);

            if (virtualAnchorBalance < totalPoolValuePrime/2) {
                gammaMulDecimals = 1e18 - (virtualAnchorBalance*1e18 /  totalPoolValuePrime);
            }else{
                uint denominator = (virtualAnchorBalance.mul(pairReserve0))/pairReserve1;
                console.log("<<<Pylon:sync::::::::den=", denominator);

                //TODO: Check that this works and there are no gamma that assume gamma is ftv/atv+ftv
                gammaMulDecimals = (virtualFloatBalance*1e18) /  totalPoolValuePrime;
            }
            // TODO: (see if make sense to insert a floor to for example 25/75)
            console.log("<<<Pylon:sync::::::::gamma'=", gammaMulDecimals/testMultiplier);
            // Calculating VAB and VFB
            console.log("<<<Pylon:sync:::::::prev:vab'=", virtualAnchorBalance/testMultiplier,
                "<<<Pylon:sync::::::::vfb'=", virtualFloatBalance/testMultiplier);

            //TODO: Think of way to adjust it by using tpv/(ftv+atv) because otherwise anchors get more fees than they should
            virtualAnchorBalance += (feeValue.mul(gammaMulDecimals))/1e18;
            console.log("<<<Pylon:sync::::::::vab'=", virtualAnchorBalance);
            virtualFloatBalance += (1e18-gammaMulDecimals).mul(feeValue)/1e18;
            console.log("<<<Pylon:sync::::::::vfb'=", virtualFloatBalance);
        }
        console.log("<<<Pylon:sync::::::::end\n\n");
    }

    // TODO: sistema di slashing, not withdraw more than a total
    function calculateLPTU(bool _isAnchor, uint _liquidity, uint _ptTotalSupply) view private returns (uint claim){
        (uint112 _reserve0, uint112 _reserve1) = getPairReservesNormalized(); // gas savings
        uint ptb = IZirconPair(pairAddress).balanceOf(address(this));
        uint lptTotalSupply = IZirconPair(pairAddress).totalSupply();
        uint userShare = _liquidity*1e18/_ptTotalSupply;
        uint pylonShare;

        if (_isAnchor) {
            //            if (gammaMulDecimals < 5e17) {
            //                share = (ptb.mul(virtualAnchorBalance))/(vfbAdjusted.add(virtualAnchorBalance));
            //            }else{
            //            }

            //            uint vfbAdjusted = (virtualFloatBalance.mul(_reserve1))/_reserve0;
            //            uint resAdjusted = reserve0.mul(_reserve1)/_reserve0;
            //            uint shittyLife = (2*uint(_reserve1).mul(_ptTotalSupply))/ptb;
            //            console.log("<<<<shittyLife", _reserve1);
            //            console.log("<<<<shittyLife", shittyLife);

            pylonShare = (lptTotalSupply.mul(virtualAnchorBalance))/(2*uint(_reserve1));

        }else{
            // TODO: gamma > 0.5
            pylonShare = ((gammaMulDecimals).mul(ptb))/1e18;
        }

        claim = (userShare.mul(pylonShare))/1e18;
        require(claim > 0, 'ZP: INSUFFICIENT_LIQUIDITY_BURNED');

        console.log("<<<<ptb", ptb);
        console.log("<<<<lptTotalSupply", lptTotalSupply);
        console.log("<<<<claim", claim);
    }

    // Burn Async send both tokens 50-50
    // Liquidity has to be sent before
    function burnAsync(address _to, bool _isAnchor) external lock {
        sync();
        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
        uint liquidity = pt.balanceOf(address(this));
        require(liquidity > 0, "ZP: Not enough liquidity inserted");

        uint ptu = calculateLPTU(_isAnchor, liquidity, pt.totalSupply());
        _safeTransfer(pairAddress, pairAddress, ptu);
        IZirconPair(pairAddress).burn(_to);
    }
    // Function That calculates the amount of reserves in PTU
    // and the amount of the minimum from liquidity and reserves
    // Helper function for burn
    function preBurn(bool isAnchor, uint _totalSupply, uint _liquidity) private returns (uint reservePT, uint amount) {
        // variables declaration
        uint _gamma = gammaMulDecimals;
        uint _vab = virtualAnchorBalance;
        (uint112 _reserve0,) = getPairReservesNormalized(); // gas savings
        (uint112 _pylonReserve0, uint112 _pylonReserve1,) = getSyncReserves();

        //Calculates maxPTs that can be serviced through Pylon Reserves
        uint pylonReserve = isAnchor ? _pylonReserve1 : _pylonReserve0;
        reservePT = ZirconLibrary.calculatePTU(isAnchor, pylonReserve, _totalSupply, uint(_reserve0), pylonReserve, _gamma, _vab);

        console.log("<<< calculatePTUToAmount", reservePT, _pylonReserve0, _pylonReserve1);
        amount = ZirconLibrary.calculatePTUToAmount(isAnchor, Math.min(reservePT, _liquidity), _totalSupply, _reserve0, pylonReserve, _gamma, _vab);
    }

    // Burn send liquidity back to user burning Pool tokens
    // The function first uses the reserves of the Pylon
    // If not enough reserves it burns The Pool Tokens of the pylon
    function burn(address _to, bool _isAnchor) external lock returns (uint amount){
        sync();
        // Selecting the Pool Token class on basis of the requested tranch to burn
        IZirconPoolToken pt = IZirconPoolToken(_isAnchor ? anchorPoolToken : floatPoolToken);
        {
            uint _totalSupply = pt.totalSupply();
            address to = _to;
            bool isAnchor = _isAnchor;
            Pair memory _pair = pair;
            address _pairAddress = pairAddress;

            // Let's get how much liquidity was sent to burn
            uint liquidity = pt.balanceOf(address(this));

            // Here we calculate max PTU to extract sync reserve + amount in reserves

            (uint reservePT, uint _amount) = preBurn(isAnchor, _totalSupply, liquidity);
            _safeTransfer(isAnchor ? _pair.token1 : _pair.token0, to, _amount);

            amount = _amount;

            if (reservePT < liquidity) {
                console.log("<<< calculateLPTU");
                _safeTransfer(_pairAddress, _pairAddress, calculateLPTU(isAnchor, liquidity.sub(reservePT), _totalSupply));
                amount += IZirconPair(_pairAddress).burnOneSide(to, !(isFloatReserve0 || !isAnchor) ); //Bool combines choice of anchor or float with which token is which in the pool
            }

            pt.burn(address(this), liquidity);
            console.log("<<<<liquidity", liquidity);
        }
        console.log("amount", amount);
        if(_isAnchor) {
            virtualAnchorBalance -= amount;
        }else{
            virtualFloatBalance -= amount;
        }
        console.log("<<<<extract end\n\n");
        _update();
    }
}
