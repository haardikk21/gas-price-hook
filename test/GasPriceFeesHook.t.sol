// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {SwapFeeLibrary} from "v4-core/libraries/SwapFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {GasPriceFeesHook} from "../src/GasPriceFeesHook.sol";
import {console} from "forge-std/console.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract TestGasPriceFeesHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    GasPriceFeesHook hook;

    // Common settings
    PoolSwapTest.TestSettings testSettings;
    IPoolManager.SwapParams params;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(GasPriceFeesHook).creationCode,
            abi.encode(manager)
        );

        // Set gas price = 10 gwei and deploy our hook
        vm.txGasPrice(10 gwei);
        hook = new GasPriceFeesHook{salt: salt}(manager);

        // Initialize a pool
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            SwapFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether
            }),
            ZERO_BYTES
        );

        // Set common settings
        testSettings = PoolSwapTest.TestSettings({
            withdrawTokens: true,
            settleUsingTransfer: true,
            currencyAlreadySent: false
        });

        params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
        });
    }

    /**
     * @notice Verifies the initial gas prices.
     */
    function checkInitialGasPrices() internal view {
        uint128 gasPrice = hook.getGasPrice();
        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 1);
    }

    /**
     * @notice Performs a swap at 10 gwei gas price.
     * @return outputFromBaseFeeSwap The output from the base fee swap.
     */
    function conductSwapAt10Gwei() internal returns (uint256) {
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromBaseFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 2);

        return outputFromBaseFeeSwap;
    }

    /**
     * @notice Performs a swap at 4 gwei gas price.
     * @return outputFromIncreasedFeeSwap The output from the increased fee swap.
     */
    function conductSwapAt4Gwei() internal returns (uint256) {
        vm.txGasPrice(4 gwei);
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromIncreasedFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 8 gwei);
        assertEq(movingAverageGasPriceCount, 3);

        return outputFromIncreasedFeeSwap;
    }

    /**
     * @notice Performs a swap at 12 gwei gas price.
     * @return outputFromDecreasedFeeSwap The output from the decreased fee swap.
     */
    function conductSwapAt12Gwei() internal returns (uint256) {
        vm.txGasPrice(12 gwei);
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1After = currency1.balanceOfSelf();
        uint256 outputFromDecreasedFeeSwap = balanceOfToken1After -
            balanceOfToken1Before;

        assertGt(balanceOfToken1After, balanceOfToken1Before);

        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverageGasPrice, 9 gwei);
        assertEq(movingAverageGasPriceCount, 4);

        return outputFromDecreasedFeeSwap;
    }

    /**
     * @notice Checks the output amounts from different gas price swaps.
     * @param outputFromBaseFeeSwap The output from the base fee swap.
     * @param outputFromIncreasedFeeSwap The output from the increased fee swap.
     * @param outputFromDecreasedFeeSwap The output from the decreased fee swap.
     */
    function checkOutputs(
        uint256 outputFromBaseFeeSwap,
        uint256 outputFromIncreasedFeeSwap,
        uint256 outputFromDecreasedFeeSwap
    ) internal view {
        console.log("Base Fee Output", outputFromBaseFeeSwap);
        console.log("Increased Fee Output", outputFromIncreasedFeeSwap);
        console.log("Decreased Fee Output", outputFromDecreasedFeeSwap);

        assertGt(outputFromDecreasedFeeSwap, outputFromBaseFeeSwap);
        assertGt(outputFromBaseFeeSwap, outputFromIncreasedFeeSwap);
    }

    /**
     * @notice Tests the fee updates with varying gas prices.
     */
    function test_feeUpdatesWithGasPrice() public {
        checkInitialGasPrices();
        uint256 outputFromBaseFeeSwap = conductSwapAt10Gwei();
        uint256 outputFromIncreasedFeeSwap = conductSwapAt4Gwei();
        uint256 outputFromDecreasedFeeSwap = conductSwapAt12Gwei();
        checkOutputs(
            outputFromBaseFeeSwap,
            outputFromIncreasedFeeSwap,
            outputFromDecreasedFeeSwap
        );
    }
}
