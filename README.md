# Gas Price Hook Live

Dynamic Fee Hooks:
-> its a type of hook that allows you to modify the swap/LP fees at any time you want

Core Idea:
-> as gas price increases onchain, decrease swap fees
-> as gas price decreases onchain, increase swap fees

around some "base" swap fees

|MIN_FEE<-------------------|BASE_FEE|------------------->MAX_FEE|

---

we're gonna keep it simple, we're gonna keep it as a proof of concept

## How dynamic fee hooks work

TL;DR

`lpFee` is managed through `Pool.State.Slot0`

Two ways to override this:

1. If you are updating the fees once-per-block or less, use `updateDynamicLPFee`
2. If you are updating for each swap, use `beforeSwap` override fee return argument

For Case (1), `PoolManager` has a function called `updateDynamicLPFee` that is only callable by the attached hook and only if pool has been set up to use dynamic fees (i.e. has the magic value set in the `PoolKey.fee` during initialization)

Hook can call this function at any point:

- in `beforeSwap` to charge a different fees for every swap action
- periodically at a fixed interval based on reaction to offchain data

---

For Case (2), the `beforeSwap` hook can return an optional third argument (default value 0 if not using) that can override LP fee for that particular swap only

Requirement: 23rd bit of the returned value must be set to `1` for it to count and consider it a valid value. Fairly simple to do using a constant provided through `LPFeeLibrary.sol`

example:

```solidity
uint24 someFees = calculateFeesForSwap();
uint24 feesWithFlag = someFees | LPFeeLibrary.OVERRIDE_FEE_FLAG;

return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feesWithFlag);
```

## mechanism design

1. there's no concept of fetching "average" gas price on a network directly onchain
2. we'll create a simple "average gas price" measurement tracker, we'll update this and recalculate the average during every swap

> NOTE: This isn't a "true" average gas price
> We are only updating it for every swap action
> you can make it more accurate by implementing every single hook function and updating average gas price regardless of
> what the action is. you can update it during addLiquidity or removeLiquidity

3. if current gas price > 110% of average gas price
   -> charge base fees \* 2
   else if
   current gas price < 90% of average gas price
   -> charge base fees / 2
   else
   charge base fees

## Calculating moving averages

MA = 0
n = 0

1. v = 10

MA = ((MA \* n) + v) / (n + 1)
n++;

MA = ((0 \* 0) + 10) / (0 + 1) = 10
n = 1

2. v = 15

MA = ((10 \* 1) + 15) / 2
= 12.5
n = 2

## Workflow

- Initially, new pool is deployed with this hook attached (dynamic fee flag is enabled)
  -> let's say this happens at a gas price of 10 gwei
  -> MA = 10 gwei

- 500 swaps happen
  -> MA = 20 gwei

- 501st swap that takes place
  -> gas price here = 25 gwei
  -> 25 > (1.1 \* 20)
  -> 501st swap will pay BASE_FEES/2 (0.25% in swap fees)
  - MA = 20...

## Types of Fees in Uniswap v4

1. LP Fees
   -> this is a % cut from the input amount during swaps
   that swappers pay to LPs for providuing liquidity
   this is how LPs make yield on their liquidity positions

2. Protocol Fees
   -> this is a cut taken from swaps that goes out to Uniswap (the organization)

3. Custom Fees (`returnDelta` hooks a.k.a. NoOp Hooks - this will be covered starting next to next week)
   -> fees that the HOOK is charging and keeping for itself in exchange for whatever services the hook is providing
   -> e.g. limit orders the hook can charge a platform fee

When we talk about dynamic fee hooks
we're specifically talking about dynamic LP FEE hooks

## Conclusion

Fill out workshop feedback form - https://atriumacademy.typeform.com/to/Z7Ad4he6
