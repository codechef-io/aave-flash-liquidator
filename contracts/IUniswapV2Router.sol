pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) virtual external returns (uint[] memory amounts);
}