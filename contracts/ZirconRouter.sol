// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.2;
import "./zircon-uniswapv2/interfaces/IUniswapV2Router02.sol";

contract ZirconRouter is IUniswapV2Router02 {

    function addSyncLiquidity(
        address anchorToken,
        address floatToken,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(anchorToken, floatToken, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, anchorToken, floatToken);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addAsyncLiquidity(
        address anchorToken,
        address floatToken,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(anchorToken, floatToken, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, anchorToken, floatToken);
        TransferHelper.safeTransferFrom(anchorToken, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(floatToken, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function removeSyncLiquidity(
        address token,
        address tokenB,
        bool isAnchor,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH) {

    }

    function removeAsyncLiquidity(
        address token,
        address tokenB,
        bool isAnchor,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH) {

    }

    //TODO: Supply/remove anchor/float synchronous/asynchronous
    function ZirconRouter(){}
}
