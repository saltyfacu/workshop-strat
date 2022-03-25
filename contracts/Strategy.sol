// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import "./interfaces/Uniswap/IUniswapV2Router02.sol";
import "./interfaces/IChefLike.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address masterchef;
    uint256 pid; //the pool id of the masterchef

    address router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address yfi = address(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e);

    constructor(address _vault, address _masterchef, uint256 _pid) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;

        maxReportDelay = 6300;
        profitFactor = 1500;
        debtThreshold = 1_000_000 * 1e18;

        masterchef = _masterchef;
        pid = _pid;
        
        want.safeApprove(masterchef, uint256(-1));
        IERC20(yfi).safeApprove(router, uint256(-1));

    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategyYearnMasterchefYFI";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        return want.balanceOf(address(this));
    }

    function _sell() internal
    {
        uint256 balanceOfYfi = IERC20(yfi).balanceOf(address(this));

        if (balanceOfYfi == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = address(yfi);
        path[1] = address(weth);
        path[2] = address(want);

        IUniswapV2Router02(router).swapExactTokensForTokens(
            balanceOfYfi,
            uint256(0),
            path,
            address(this),
            now
        );
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        IChefLike(masterchef).deposit(pid, 0); //why?

        _sell(); // we still need to code this

        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 balanceOfWant = want.balanceOf(address(this));

        if (assets > debt) {
            _debtPayment = _debtOutstanding;
            _profit = assets - debt;

            uint256 amountToFree = _profit.add(_debtPayment);

            if (amountToFree > 0 && balanceOfWant < amountToFree) {
                liquidatePosition(amountToFree);

                uint256 newLoose = want.balanceOf(address(this));

                //if we dont have enough money adjust _debtOutstanding and only change profit if needed
                if (newLoose < amountToFree) {
                    if (_profit > newLoose) {
                        _profit = newLoose;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(
                            newLoose - _profit,
                            _debtPayment
                        );
                    }
                }
            }
        } else {
            // we lost money :(
            _loss = debt - assets;
        }

    }

    function adjustPosition(uint256 _debtOutstanding) internal override {

        uint256 balanceOfWant = want.balanceOf(address(this));

        if (balanceOfWant > 0) {
            IChefLike(masterchef).deposit(pid, balanceOfWant);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            uint256 assetsToFree = _amountNeeded.sub(totalAssets);
            IChefLike(masterchef).withdraw(pid, assetsToFree);

            _liquidatedAmount = want.balanceOf(address(this));

        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
