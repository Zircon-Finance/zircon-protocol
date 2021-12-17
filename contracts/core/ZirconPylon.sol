pragma solidity ^0.5.16;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './libraries/Math.sol';
import './ZirconPair.sol';

contract ZirconPylon {
    using SafeMath for uint;

    address public pairAddress;

    address public floatToken;
    address public anchorToken;
    bool floatIsReserve0;

    uint virtualAnchorBalance;
    uint virtualFloatBalance;

    uint gammaMulDecimals; //Name represents the fact that this is always the numerator of a fraction with 10**18 as denominator.

    uint lastK;
    uint lastPoolTokens;

    uint percentageReserve; //Amount reserved for liquidity withdrawals/insertions

    uint ownedPoolTokens; //Used to track the pool tokens it owns but may not necessarily contain as balanceOf

    //Calls dummy function with lock modifier
    modifier pairUnlocked() {
        ZirconPair(pairAddress).tryLock();
        _;
    }

    modifier blockRecursion() {
        //TODO: Should do some kind of block height check to ensure this user hasn't already called any of these functions
        _;
    }

    constructor() public {
        // TODO: Create Anchor/Float ZirconPoolToken CREATE2
    }

    function supplyFloatLiquidity() external pairUnlocked {
        //Mints Float pool tokens to the user according to the value supplied
        //Value is derived from TWAP pool oracle
        //Follows Uniswap model — tokens are pre-sent to the contract by the router.
        sync();

        //mintFloatTokens()

        //Then sends liquidity if it has the appropriate reserves for it
        _sendLiquidity();
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

        //Only continues if it's called by pair itself or if the pair is unlocked
        //Which ensures it's not called within UniswapV2Callee
        if(msg.sender != pairAddress) {
            ZirconPair(pairAddress).tryLock();
        }

        //So this thing needs to get pool reserves, get the price of the float asset in anchor terms
        //Then it applies the base formula:
        //Adds fees to virtualFloat and virtualAnchor
        //And then calculates Gamma so that the proportions are correct according to the formula

        (uint112 reserve0, uint112 reserve1,) = ZirconPair(pairAddress).getReserves();
        uint price;
        uint totalPoolValue;
        uint totalPoolValuePrime;

        uint poolTokensPrime = ZirconPair(pairAddress).totalSupply();
        uint poolTokenBalance = ZirconPair(pairAddress).balanceOf(address(this));

        if(floatIsReserve0) {
            //Todo: Don't actually need oracle here, just relatively stable amount of reserve1. Or do we?
            //price = oracle.getFloatPrice(reserve0, reserve1, floatToken, anchorToken);
            //TODO: SafeMath
            //totalPoolValuePrime = reserve1.mul(2).mul(poolTokenBalance)/poolTokensPrime; //Adjusted by the protocol's share of the entire pool.
        } else {
            //price = oracle.getFloatPrice(reserve1, reserve0, floatToken, anchorToken);
            //TODO: SafeMath
            //totalPoolValuePrime = reserve0.mul(2).mul(poolTokenBalance)/poolTokensPrime;
        }

        uint kPrime = reserve0 * reserve1;

        //Todo: Fix with actual integer math
        uint feeValue = totalPoolValuePrime.mul(1 - Math.sqrt(lastK/kPrime).mul(poolTokensPrime)/lastPoolTokens);

        virtualAnchorBalance += feeValue.mul(virtualAnchorBalance)/totalPoolValuePrime;
        virtualFloatBalance += feeValue.mul(1-virtualAnchorBalance/totalPoolValuePrime);


        //Gamma is the master variable used to define withdrawals
        gammaMulDecimals = 10**18 - (virtualAnchorBalance.mul(10**18) / totalPoolValuePrime.mul(10**18)); //1 - ATV/TPV but multiplied by 10**18 due to integer math shit


    }

    //Called at the end of supply functions to supply any available 50-50 liquidity to underlying pool
    function _sendLiquidity() private {

    }


    //Called by remove functions if a withdrawal requires underlying liquidity extraction
    function _extractFloatLiquidity() private {
        //Sends tokens from self if it has them
        //Otherwise directs pool to send them to user

        //TODO: maybe we can do some kind of self-flash swap to make it swap with less slippage (before liquidity is removed)?
        //TODO: Also to avoid needless ERC-20 transfers
        //TODO: Or just literally send tokens from the pool
    }

    function _extractAnchorLiquidity() private {
        //redeems owned pool tokens, swaps them with the pool to deliver only anchor asset
    }

}
