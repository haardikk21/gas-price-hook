// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

contract GasPriceFeesHook is BaseHook {
    using LPFeeLibrary for uint24;

    // Keeping track of the moving average gas price
    uint128 public movingAverageGasPrice;
    // How many times has the moving average been updated?
    // Needed as the denominator to update it the next time based on the moving average formula
    uint104 public movingAverageGasPriceCount;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%

    error MustUseDynamicFee();

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        updateMovingAverage();
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    )
        external
        override
        onlyByManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = getFee();
        manager.updateDynamicLPFee(key, fee);
        return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    function getFee() internal view returns (uint24) {
        uint128 gasPrice = getGasPrice();

        // if gasPrice > movingAverageGasPrice * 1.1, then half the fees
        if (gasPrice > (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2;
        }

        // if gasPrice < movingAverageGasPrice * 0.9, then double the fees
        if (gasPrice < (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }

        return BASE_FEE;
    }

    // Update our moving average gas price
    function updateMovingAverage() internal {
        uint128 gasPrice = getGasPrice();

        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice =
            ((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) /
            (movingAverageGasPriceCount + 1);

        movingAverageGasPriceCount++;
    }

    // Gets the current gas price of this transaction
    // There is no high-level function in Solidity for this, but Solidity-assembly allows this
    function getGasPrice() public view returns (uint128) {
        uint128 gasPrice;
        assembly {
            gasPrice := gasprice()
        }
        return gasPrice;
    }
}
