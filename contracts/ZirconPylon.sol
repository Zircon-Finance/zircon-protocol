pragma solidity ^0.4.0;

import './interfaces/IZirconPair.sol';

contract ZirconPylon {

    address public pairAddress;

    address public floatToken;
    address public anchorToken;

    uint virtualAnchorBalance;
    uint lastK;
    uint lastPTSupply;

    uint percentageReserve;

    bool distressed;

    //Calls dummy function with lock modifier
    modifier pairUnlocked() {
        IZirconPair(pairAddress).tryLock();
        _;
    }

    modifier blockRecursion() {
        //TODO: Should do some kind of block height check to ensure this user hasn't already called any of these functions
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
            IZirconPair(pairAddress).tryLock();
        }


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
    }

    function _extractAnchorLiquidity() private {
        //redeems owned pool tokens, swaps them with the pool to deliver only anchor asset
    }

}
