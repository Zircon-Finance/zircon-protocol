pragma solidity ^0.5.16;

import "./SafeMath.sol";

library ZirconLibrary {
    using SafeMath for uint256;
    uint public constant MINIMUM_LIQUIDITY = 10**3;

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

        //Expresses b1 in units of reserve0
        uint px = _reserve0.mul(_b1)/_reserve1;

        if (px > _b0) {
            maxX = _b0;
            maxY = _b0.mul(_reserve1)/_reserve0; //b0 in units of reserve1
        } else {
            maxX = px; //max is b1 but in reserve0 units
            maxY = _b1;
        }
    }


    // This function converts amount, specifing which tranch with @isAnchor, to pool token share
    // @_amount is the quantity to convert
    // @_totalSupply is the supply of the pt's tranch
    // @reserve0, @_gamma, @vab are the variables needed to the calculation of the amount
    function calculatePTU(bool _isAnchor, uint _amount, uint _totalSupply, uint _reserve0, uint _reservePylon0, uint _gamma, uint _vab) pure internal returns (uint liquidity){
        if (_isAnchor) {
            // TODO: Check the MINIMUM LIQUIDITY SUBSTRACTION
            liquidity = (_amount.mul(_totalSupply == 0 ? 1e18 : _totalSupply.mul(1e18)/_vab)/1e18)
                .sub(_totalSupply == 0 ? MINIMUM_LIQUIDITY : 0);
        }else {
            // TODO: Check the MINIMUM LIQUIDITY SUBSTRACTION
            uint numerator = _totalSupply == 0 ? _amount.mul(1e18) : _amount.mul(_totalSupply);
            uint resTranslated = _reserve0.mul(_gamma).mul(2)/1e18;
            uint denominator = _totalSupply == 0 ? _gamma.mul(2) : (_reservePylon0.add(resTranslated));
            liquidity = (numerator/denominator).sub(_totalSupply == 0 ? MINIMUM_LIQUIDITY : 0);
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

    function slashLiabilityOmega(uint tpvAnchorTranslated, uint anchorReserve, uint gammaMulDecimals, uint virtualAnchorBalance) pure internal returns (uint omegaMulDecimals) {

        //Omega is the "survival factor" i.e how much of the anchor balance survives slashing and can be withdrawn.
        //It's applied to the user's liquidity tokens to avoid changing other core functions.
        //This adjustment is only used for share calculations, the full amount of tokens is removed.
        omegaMulDecimals = ((1e18 - gammaMulDecimals).mul(tpvAnchorTranslated))/(virtualAnchorBalance - anchorReserve);

    }
}
