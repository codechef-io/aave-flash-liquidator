pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IUniswapV2Factory.sol";
import "./ILendingPoolAddressProvider.sol";
import "./ILendingPool.sol";
import "./ICallee.sol";
import "./DydxFlashloanBase.sol";
import "./IUniswapV2Router.sol";
import "./OneInch.sol";
import "./IAaveLiquidator.sol";
import "hardhat/console.sol";

contract AaveLiquidator is IAaveLiquidator, Ownable, ICallee, DydxFlashloanBase {
    address public lendingPoolAddressProvider = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public dydxSoloAddress = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    address public oneInchRouterAddress = 0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e;
    address public uniswapRouter02Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public uniswapFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public defaultDydxBorrowAsset = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //default DAI
    address public uniswapIntermediateAsset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    using SafeERC20 for IERC20;

    modifier onlyLendingPool() {
        require(dydxSoloAddress == _msgSender(), "Ownable: caller is not the dydx solo address");
        _;
    }

    constructor() public Ownable() {
    }

    struct LiquidationData {
        address collateral;
        address debt;
        address user;
        uint256 debtToPay;
        //dydx data
        uint256 repayAmount;
        bool useIntermediateDydxToken;
        bool useUniswap;
    }

    function liquidateWithTradedDydx(
        address _collateral,
        address _debt,
        address _user,
        uint256 _dydxBorrowAmount,
        bool _useUniswap
    ) override public onlyOwner {
        require(unhealthyUser(_user), 'user was healthy');
        ISoloMargin solo = ISoloMargin(dydxSoloAddress);
        uint256 marketId = _getMarketIdFromTokenAddress(dydxSoloAddress, defaultDydxBorrowAsset);
        uint256 repayAmount = _getRepaymentAmountInternal(_dydxBorrowAmount);
        safeAllow(defaultDydxBorrowAsset, dydxSoloAddress);
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);
        operations[0] = _getWithdrawAction(marketId, _dydxBorrowAmount);
        operations[1] = _getCallAction(
            abi.encode(LiquidationData(
            {
            collateral : _collateral,
            debt : _debt,
            user : _user,
            debtToPay : _dydxBorrowAmount,
            repayAmount : repayAmount,
            useIntermediateDydxToken : true,
            useUniswap : _useUniswap
            }))
        );
        operations[2] = _getDepositAction(marketId, repayAmount);
        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();
        solo.operate(accountInfos, operations);
    }

    function liquidateWithNativeDydx(
        address _collateral,
        address _debt,
        address _user,
        uint256 _debtToPay,
        bool _useUniswap
    ) override public onlyOwner {
        require(unhealthyUser(_user), 'user was healthy');
        ISoloMargin solo = ISoloMargin(dydxSoloAddress);
        uint256 marketId = _getMarketIdFromTokenAddress(dydxSoloAddress, _debt);
        uint256 repayAmount = _getRepaymentAmountInternal(_debtToPay);
        safeAllow(_debt, dydxSoloAddress);
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);
        operations[0] = _getWithdrawAction(marketId, _debtToPay);
        operations[1] = _getCallAction(
        // Encode MyCustomData for callFunction
            abi.encode(LiquidationData(
            {
            collateral : _collateral,
            debt : _debt,
            user : _user,
            debtToPay : _debtToPay,
            repayAmount : repayAmount,
            useIntermediateDydxToken : false,
            useUniswap : _useUniswap
            })
            )
        );
        operations[2] = _getDepositAction(marketId, repayAmount);
        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();
        solo.operate(accountInfos, operations);
    }

    function liquidate(
        address _collateral,
        address _debt,
        address _user,
        uint256 _debtToPay,
        bool _receiveaToken
    ) public onlyLendingPool {
        ILendingPoolAddressesProvider addressProvider = ILendingPoolAddressesProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());
        safeAllow(_debt, address(lendingPool));
        uint256 allowanceToLiquidate = IERC20(_debt).allowance(address(this), address(lendingPool));
        //      require(allowanceToLiquidate == _debtToPay, 'allowance to liquidate isnt high enough');
        lendingPool.liquidationCall(_collateral, _debt, _user, _debtToPay, _receiveaToken);
    }

    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public override virtual {
        LiquidationData memory liquidationData = abi.decode(data, (LiquidationData));

        if (liquidationData.useIntermediateDydxToken == true) {

            uint256 borrowedAmount = IERC20(defaultDydxBorrowAsset).balanceOf(address(this));

            //if the borrowed asset doesnt equal the debt, exchange
            if (defaultDydxBorrowAsset != liquidationData.debt) {
                console.log('going to swap traded for debt');
                uniswap(defaultDydxBorrowAsset, liquidationData.debt, borrowedAmount, 0);
                console.log('just swapped traded for debt');
            }

            uint256 availableDebtTokens = IERC20(liquidationData.debt).balanceOf(address(this));

            liquidate(liquidationData.collateral, liquidationData.debt, liquidationData.user, availableDebtTokens, false);
            uint256 receivedCollateral = IERC20(liquidationData.collateral).balanceOf(address(this));

            //whatever is left of the things we traded for -> trade it for what we borrowed
            uint256 currentBalance = IERC20(liquidationData.debt).balanceOf(address(this));
            if (currentBalance > 0) {
                uint256 repayBalance = oneInchSwap(liquidationData.debt, defaultDydxBorrowAsset, currentBalance, 0);
            }

            if (liquidationData.useUniswap) {
                uniswap(liquidationData.collateral, defaultDydxBorrowAsset, receivedCollateral, liquidationData.repayAmount);
            } else {
                oneInchSwap(liquidationData.collateral, defaultDydxBorrowAsset, receivedCollateral, liquidationData.repayAmount);
            }
            uint256 balOfLoanedToken = IERC20(defaultDydxBorrowAsset).balanceOf(address(this));
        } else {
            //we need to receive the undedlying asset to be able to trade
            liquidate(liquidationData.collateral, liquidationData.debt, liquidationData.user, liquidationData.debtToPay, false);

            uint256 receivedCollateral = IERC20(liquidationData.collateral).balanceOf(address(this));

            if (liquidationData.useUniswap) {
                uniswap(liquidationData.collateral, liquidationData.debt, receivedCollateral, liquidationData.repayAmount);
            } else {
                oneInchSwap(liquidationData.collateral, liquidationData.debt, receivedCollateral, liquidationData.repayAmount);
            }
            uint256 balOfLoanedToken = IERC20(liquidationData.debt).balanceOf(address(this));
        }
    }

    function uniswap(address _fromToken, address _toToken, uint256 _fromAmount, uint256 _minimumToAmount) private {
        safeAllow(_fromToken, uniswapRouter02Address);
        IUniswapV2Router uniswapRouter = IUniswapV2Router(uniswapRouter02Address);

        if (directPairExists(_fromToken, _toToken)) {
            address[] memory path = new address[](2);
            path[0] = address(_fromToken);
            path[1] = address(_toToken);
            uniswapRouter.swapExactTokensForTokens(
                _fromAmount,
                _minimumToAmount,
                path,
                address(this),
                block.timestamp + 1
            );
        } else {
            address[] memory path = new address[](3);
            path[0] = address(_fromToken);
            path[1] = address(uniswapIntermediateAsset);
            path[2] = address(_toToken);
            uniswapRouter.swapExactTokensForTokens(
                _fromAmount,
                _minimumToAmount,
                path,
                address(this),
                block.timestamp + 1
            );
        }
    }

    function oneInchSwap(address fromToken, address toToken, uint256 fromAmount, uint256 minimumRequiredTo) private returns (uint256 returnAmount){
        OneInch oneInch = OneInch(oneInchRouterAddress);
        (uint256 expectedAmount, uint256[] memory distribution) = oneInch.getExpectedReturn(IERC20(fromToken), IERC20(toToken), fromAmount, 10, 0);
        uint256 currentBalance = IERC20(toToken).balanceOf(address(this));
        require(currentBalance + expectedAmount >= minimumRequiredTo, 'expected return from exchange was not enough');
        safeAllow(fromToken, oneInchRouterAddress);
        uint256 returnAmount = oneInch.swap(IERC20(fromToken), IERC20(toToken), fromAmount, minimumRequiredTo, distribution, 0);
        return returnAmount;
    }

    function setLendingPoolAddressProvider(address _provider) public onlyOwner {
        lendingPoolAddressProvider = _provider;
    }

    function setDydxSoloAddress(address _dydxSoloAddress) public onlyOwner {
        dydxSoloAddress = _dydxSoloAddress;
    }

    function setOneInchRouterAddress(address _oneInchAddress) public onlyOwner {
        oneInchRouterAddress = _oneInchAddress;
    }

    function setUniswapIntermediateAsset(address _uniswapIntermediateAsset) public onlyOwner {
        uniswapIntermediateAsset = _uniswapIntermediateAsset;
    }

    function setUniswapRouter02Address(address _uniswapRouter02Address) public onlyOwner {
        uniswapRouter02Address = _uniswapRouter02Address;
    }

    function setUniswapFactoryAddress(address _uniswapFactoryAddress) public onlyOwner {
        uniswapFactoryAddress = _uniswapFactoryAddress;
    }

    function setDefaultDydxBorrowAsset(address _defaultDydxBorrowAsset) public onlyOwner {
        defaultDydxBorrowAsset = _defaultDydxBorrowAsset;
    }

    function unhealthyUser(address _user) public view returns (bool){
        ILendingPoolAddressesProvider addressProvider = ILendingPoolAddressesProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());
        (uint totalCollateralETH, uint totalDebtEth, uint availableBorrowsETH,  uint currentLiquidationThreshold, uint ltv, uint hf) = lendingPool.getUserAccountData(_user);
        return hf < 1 ether;
    }

    function safeAllow(address asset, address allowee) private {
        IERC20 token = IERC20(asset);

        if (token.allowance(address(this), allowee) == 0) {
            token.safeApprove(allowee, uint256(-1));
        }
    }

    function directPairExists(address fromToken, address toToken) view public returns (bool) {
        return IUniswapV2Factory(uniswapFactoryAddress).getPair(fromToken, toToken) != address(0);
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function approve(address _asset, address _beneficiary) external onlyOwner {
        safeAllow(_asset, _beneficiary);
    }

    function transferTo(address _asset, address _beneficiary,  uint256 _amount) external onlyOwner {
        IERC20(_asset).transfer(address(_beneficiary), _amount);
    }

}