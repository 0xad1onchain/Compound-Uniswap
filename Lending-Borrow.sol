pragma solidity ^0.5.12;

interface UniswapRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IWeth {
    function withdraw(uint256 wad) external;

    function balanceOf(address) external view returns (uint256);
}

interface Erc20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
}

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function repayBorrow(uint256) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

interface CEth {
    function mint() external payable;

    function borrow(uint256) external returns (uint256);

    function repayBorrow() external payable;

    function borrowBalanceCurrent(address) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

interface PriceFeed {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

contract BorrowDAI {
    event Log(string, uint256);

    struct Balances {
        uint256 ethBalance;
        uint256 cEthBalance;
        uint256 daiBalance;
    }

    address public cEthAddress = 0x41B5844f4680a8C38fBb695b7F9CFd1F64474a72;
    address public comptrollerAddress =
        0x5eAe89DC1C671724A672ff0630122ee834098657;
    address public openPriceFeedAddress =
        0xbBdE93962Ca9fe39537eeA7380550ca6845F8db7;
    address public underlyingDAIAddress =
        0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
    address public cDaiAddress = 0xF0d0EB522cfa50B716B3b1604C4F0fA6f04376AD;

    address public uniswapRouterAddress =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public wethAddress = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;

    CEth cEth;
    Comptroller comptroller;
    PriceFeed priceFeed;
    Erc20 daiErc20;
    CErc20 cDai;
    UniswapRouter router;
    IWeth weth;

    Balances public balances;

    constructor() public {
        cEth = CEth(cEthAddress);
        comptroller = Comptroller(comptrollerAddress);
        priceFeed = PriceFeed(openPriceFeedAddress);
        daiErc20 = Erc20(underlyingDAIAddress);
        cDai = CErc20(cDaiAddress);
        router = UniswapRouter(uniswapRouterAddress);
        weth = IWeth(wethAddress);
    }

    function updateBalances() public {
        uint256 _ethBalance = address(this).balance;
        uint256 _cEthBalance = cEth.balanceOf(address(this));
        uint256 _daiBalance = daiErc20.balanceOf(address(this));

        balances = Balances({
            ethBalance: _ethBalance,
            cEthBalance: _cEthBalance,
            daiBalance: _daiBalance
        });
    }

    function borrowDai() public {
        updateBalances();

        // Deposit ETH to get cETH
        cEth.mint.value(balances.ethBalance).gas(150000)();
        address[] memory cEthMarket = new address[](1);
        cEthMarket[0] = cEthAddress;

        // Inform market about adding ETH as collateral
        uint256[] memory errorEntry = comptroller.enterMarkets(cEthMarket);
        if (errorEntry[0] != 0) {
            revert("eth market entry failed");
        }

        // Fetch liquidity in USD
        (uint256 error2, uint256 liquidity, uint256 shortfall) =
            comptroller.getAccountLiquidity(address(this));
        if (error2 != 0) {
            revert("something went wrong while getting liquidity");
        }

        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        emit Log("borrow limit in USD", liquidity / (10**8));

        // uint ammountToBorrow = liquidity / (10 ** 8);
        uint256 ammountToBorrow = (liquidity * 75) / 100;

        //Borrow from cDai
        uint256 borrowResult = cDai.borrow(ammountToBorrow);
        emit Log("Borrowed Result", borrowResult);

        uint256 borrowBalance = cDai.borrowBalanceCurrent(address(this));
        emit Log("borrowBalance", borrowBalance);

        updateBalances();
    }

    function swapDaiToEth() public {
        updateBalances();
        daiErc20.approve(address(uniswapRouterAddress), balances.daiBalance);

        require(
            daiErc20.allowance(address(this), address(uniswapRouterAddress)) ==
                balances.daiBalance,
            "Not enough approved balance"
        );

        //TODO: Find a good trustable price oracle on the testnets
        // uint256 approxPrice = priceFeed.getUnderlyingPrice(cDaiAddress);

        address[] memory path = new address[](2);
        path[0] = address(underlyingDAIAddress);
        path[1] = router.WETH();

        uint256[] memory amounts =
            router.swapExactTokensForTokens(
                balances.daiBalance,
                1,
                path,
                address(this),
                block.timestamp
            );

        emit Log("Swapped amounts", amounts[1]);

        uint256 wethReceived = weth.balanceOf(address(this));
        weth.withdraw(wethReceived);

        updateBalances();
    }

    function lendEth() public {
        updateBalances();

        //Mint cEth tokens by lending Eth
        cEth.mint.value(balances.ethBalance)();
    }

    //Imp! for contract to receive any ETH
    function() external payable {}

    function getEtherBack() public {
        address(msg.sender).transfer(address(this).balance);
    }
}
