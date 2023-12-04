// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address uniswapV2Pair);
}

contract Lika is ERC20, Ownable(msg.sender)
{
    string constant TOKEN_NAME = "Lika";
    string constant TOKEN_SYMBOL = "LIKA";

    uint8 internal constant DECIMAL_PLACES = 18;
    uint256 constant TOTAL_SUPPLY = 3 * 10**9 * 10**DECIMAL_PLACES;

    mapping (address => bool) private _isExcludedFromFee;

    uint256 public BUY_TAX = 3;
    uint256 public SELL_TAX = 3;
    uint256 constant TAX_DIV = 1000;

    uint256 constant BURN_FEE = 50;
    uint256 constant ECOSYSTEM_FEE = 20;
    uint256 constant POOL_LIQUIDITY_FEE = 30;

    address public _ecosystemAddress;
    address public _stakingAddress;

    IRouter public _router;
    address public _pair;

    uint256 public swapThreshold = TOTAL_SUPPLY / 5000;
    
    bool public tradingEnabled = false;

    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        super._mint(msg.sender, TOTAL_SUPPLY);

        // Create a uniswap pair for this new token
        _router = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _pair = IFactory(_router.factory())
            .createPair(address(this), _router.WETH());

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[address(0)] = true;
    }

    function decimals() public pure override returns (uint8) {
        return DECIMAL_PLACES;
    }

    function _update(address from, address to, uint256 value) internal override {
        
        bool isBuy = from == _pair || from == address(_router);
        bool isSell = to == _pair || to == address(_router);

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to] && tx.origin != owner()) {
            if (!tradingEnabled) {
                revert("Trading not yet enabled!");
            }

            if (isBuy) {
                uint256 tax = value * BUY_TAX / TAX_DIV;
                super._update(from, address(this), tax);

                value = value - tax;
            }

            if (isSell) {
                uint256 tax = value * SELL_TAX / TAX_DIV;
                super._update(from, address(this), tax);

                value = value - tax;
            }
        }

        super._update(from, to, value);
    }

    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading already enabled!");

        tradingEnabled = true;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _approve(address(this), address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_router), tokenAmount);

        // add the liquidity
        _router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function setEcosystemAddress(address ecoAddress) external onlyOwner() {
        _ecosystemAddress = ecoAddress;
    }

    function setStakingAddress(address stakingAddress) external onlyOwner() {
        _stakingAddress = stakingAddress;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).transfer(owner(),_amount);
    }

    function withdrawETH(uint256 _ethAmount) external onlyOwner {
        ( bool success,) = owner().call{value: _ethAmount}("");
        require(success, "Withdrawal was not successful");
    }
    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
}