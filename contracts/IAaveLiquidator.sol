pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

abstract contract IAaveLiquidator {
    function liquidateWithNativeDydx(
        address _collateral,
        address _debt,
        address _user,
        uint256 _debtToPay,
        bool _useUniswap
    ) virtual public;

    function liquidateWithTradedDydx(
        address _collateral,
        address _debt,
        address _user,
        uint256 _dydxBorrowAmount,
        bool _useUniswap
    ) virtual public;
}