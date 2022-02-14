pragma solidity ^0.5.16;

import "./SafeMath.sol";

library ZirconLibrary {
    using SafeMath for uint256;
    // calculates the CREATE2 address for a pair without making any external calls
    //TODO: Update init code hash with Zircon Pylon code hash
    function pylonFor(address factory, address tokenA, address tokenB, address pair) internal pure returns (address pair) {
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(tokenA, tokenB, pair)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    // fetches and gets Reserves
    function getSyncReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveF, uint reserveA) {
        (reserveF, reserveA) = IZirconPylon(pylonFor(factory, tokenA, tokenB)).getSyncReserves();
    }

    // fetches and sorts the reserves for a pair
    function maximumSync(uint reserve, uint reservePylon) external pure returns (uint maximum) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IZirconPylon(pylonFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // Same Function as Uniswap Library, used here for incompatible solidity versions
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // TODO: check getAmountsOut function of v2 library, they use a slightly different formula
    // This function takes two variables and look at the maximum possible with the ration given by the reserves
    // @pR0, @pR1 the pair reserves
    // @b0, @b1 the balances to calculate
    function _getMaximum(uint _reserve0, uint _reserve1, uint _b0, uint _b1) pure internal returns (uint maxX, uint maxY)  {
        uint px = _reserve0.mul(_b1)/_reserve1;
        if (px > _b0) {
            maxX = _b0;
            maxY = _b0.mul(_reserve1)/_reserve0;
        } else {
            maxX = px;
            maxY = _b1;
        }
    }


    // This function converts amount, specifing which tranch with @isAnchor, to pool token share
    // @_amount is the quantity to convert
    // @_totalSupply is the supply of the pt's tranch
    // @reserve0, @_gamma, @vab are the variables needed to the calculation of the amount
    function calculatePTU(bool _isAnchor, uint _amount, uint _totalSupply, uint _reserve0, uint _reservePylon0, uint _gamma, uint _vab) pure internal returns (uint liquidity){
        if (_isAnchor) {
            liquidity = ((_amount.mul(_totalSupply == 0 ? 1e18 : _totalSupply))/_vab);
        }else {
            uint numerator = _totalSupply == 0 ? _amount.mul(1e18) : _amount.mul(_totalSupply);
            uint resTranslated = _reserve0.mul(_gamma).mul(2)/1e18;
            uint denominator = _reserve0 == 0 ? _gamma.mul(2) : (_reservePylon0.add(resTranslated));
            liquidity = numerator/denominator;
        }
    }

    // This function converts pool token share, specifing which tranch with @isAnchor, to token amount
    // @_ptuAmount is the quantity to convert
    // @_totalSupply is the supply of the pt of the tranch
    // @reserve0, @_gamma, @vab are the variables needed to the calculation of the amount
    function calculatePTUToAmount(bool _isAnchor, uint _ptuAmount, uint _totalSupply, uint _reserve0, uint _reservePylon0, uint _gamma, uint _vab) pure internal returns (uint amount) {
        if (_isAnchor) {
            amount = _vab.mul(_ptuAmount)/_totalSupply;
        } else {
            uint numerator = (_ptuAmount.mul(_gamma).mul(2))/1e18;
            amount = (numerator.mul(_reserve0).add(_reservePylon0))/_totalSupply;
        }
    }
}
