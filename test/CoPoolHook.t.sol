// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {console} from "forge-std/console.sol";
import {CoPoolHook} from "../src/CoPoolHook.sol";

import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {LiquidityMath} from "v4-core/libraries/LiquidityMath.sol";

contract CoPoolHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    // manager = PoolManager
    CoPoolHook hook;

    Currency token0;
    Currency token1;

    function setUp() public {
        // Step 1 + 2
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        (token0, token1) = deployMintAndApprove2Currencies();

        // Deploy our TOKEN contract
        // uint160 flags = uint160(
        //     Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        //         | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
        // );
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
        );

        address hookAddress = address(flags);

        deployCodeTo("CoPoolHook.sol", abi.encode(manager), hookAddress);

        // Deploy our hook
        hook = CoPoolHook(hookAddress);

        // Initialize a pool
        (key,) = initPool(
            token0, // Currency 0 = Bond
            token1, // Currency 1 = Counterparty
            hook, // Hook Contract
            100, // Swap Fees - 1 bps -- fee / 100 * 2
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // Add initial liquidity to the pool

        // Some liquidity from -60 to +60 tick range
        // uint256 tokenId1 = 120;
        // uint256 tokenId2 = 121;
        // uint256 tokenId3 = 122;
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: -60,
        //         tickUpper: 60,
        //         liquidityDelta: 10 ether,
        //         salt: bytes32(0)
        //     }),
        //     ZERO_BYTES
        // );
        // // Some liquidity from -120 to +120 tick range
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: -120,
        //         tickUpper: 120,
        //         liquidityDelta: 10 ether,
        //         salt: bytes32(0)
        //     }),
        //     ZERO_BYTES
        // );
        // // some liquidity for full range
        // modifyLiquidityRouter.modifyLiquidity(
        //     key,
        //     IPoolManager.ModifyLiquidityParams({
        //         tickLower: TickMath.minUsableTick(60),
        //         tickUpper: TickMath.maxUsableTick(60),
        //         liquidityDelta: 10 ether,
        //         salt: bytes32(0)
        //     }),
        //     ZERO_BYTES
        // );
    }

    function test_deposit() public {
        // Start by bonding the bondToken

        // Approve and single stake token1
        MockERC20(Currency.unwrap(token0)).approve(address(hook), 5 ether);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), 1 ether);
        hook.deposit(1 ether, false); // false of isZero
        hook.deposit(5 ether, true); // true of isZero

        // Check the hook's delta of token0
        int256 deltaOfToken0 = hook.deltaOfToken0();
        // console.log("test_deposit() - deltaOfToken0: ", deltaOfToken0);
        assertEq(deltaOfToken0, -5 ether);

        int256 deltaOfToken1 = hook.deltaOfToken1();
        // console.log("test_deposit() - deltaOfToken1: ", deltaOfToken1);
        assertEq(deltaOfToken1, -1 ether);

        uint256 token1Balance = hook.token1BalanceOf(address(this));
        // console.log("test_deposit() - token1BalanceOf(address(this)): ", token1Balance);
        assertEq(token1Balance, 1 ether);

        uint256 token0Balance = hook.token0BalanceOf(address(this));
        // console.log("test_deposit() - token0BalanceOf(address(this)): ", token0Balance);
        assertEq(token0Balance, 5 ether);
    }

    function test_withdraw_error() public {
        // Start by bonding the bondToken

        // Approve and single stake token1
        MockERC20(Currency.unwrap(token1)).approve(address(hook), 1 ether);
        vm.expectRevert("Insufficient balance for token1");
        hook.withdraw(1 ether, false); // false of isZero
    }

    function test_withdraw() public {
        MockERC20(Currency.unwrap(token0)).approve(address(hook), 2 ether);
        MockERC20(Currency.unwrap(token1)).approve(address(hook), 2 ether);
        hook.deposit(2 ether, false); // false of isZero
        hook.deposit(2 ether, true); // false of isZero
        hook.withdraw(1 ether, false); // false of isZero
        hook.withdraw(1 ether, true); // false of isZero

        // Check the hook's delta of token0
        int256 deltaOfToken0 = hook.deltaOfToken0();
        // console.log("test_withdraw() - deltaOfToken0: ", deltaOfToken0);
        assertEq(deltaOfToken0, -1 ether);

        int256 deltaOfToken1 = hook.deltaOfToken1();
        // console.log("test_withdraw() - deltaOfToken1: ", deltaOfToken1);
        assertEq(deltaOfToken1, -1 ether);

        uint256 token1Balance = hook.token1BalanceOf(address(this));
        // console.log("test_deposit() - token1BalanceOf(address(this)): ", token1Balance);
        assertEq(token1Balance, 1 ether);

        uint256 token0Balance = hook.token0BalanceOf(address(this));
        // console.log("test_deposit() - token0BalanceOf(address(this)): ", token0Balance);
        assertEq(token0Balance, 1 ether);
    }

    // Here we unapprove the token0 from the sender, and leverage the token0 in hook.
    function test_addSingleToken0Liquidity_error(address caller) public {
        // Start by bonding the bondToken

        // Approve and stake token1
        // MockERC20(Currency.unwrap(token0)).approve(address(hook), 10 ether);

        MockERC20(Currency.unwrap(token1)).approve(address(hook), 10 ether);
        // Unapprove token1 from swapRouter and modifyLiquidityRouter to prevent it from being staked.
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), 0);
        MockERC20(Currency.unwrap(token1)).approve(address(modifyLiquidityRouter), 0);
        hook.deposit(10 ether, false);

        bytes memory action = hook.COPOOL();
        uint8 tokenSelection = 3;

        bytes memory hookData = abi.encode(action, tokenSelection);

        uint256 tokenId = 123;
        // This will single stake token0 and co-pool it against the token1 already deposited.
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         CustomRevert.WrappedError.selector,
        //         address(uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)),
        //         IHooks.afterAddLiquidity.selector,
        //         "",
        //         abi.encodeWithSelector(
        //             Hooks.HookCallFailed.selector, abi.encodeWithSelector(CoPoolHook.InvalidTokenSelection.selector)
        //         )
        //     )
        // );
        // vm.expectRevert(abi.encodeWithSelector(CoPoolHook.InvalidTokenSelection.selector));
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         CustomRevert.WrappedError.selector,
        //         address(uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)), // Derived from Hooks
        //         IHooks.afterAddLiquidity.selector, // Function selector
        //         "", // Placeholder for any additional data
        //         abi.encodeWithSelector(CoPoolHook.InvalidTokenSelection.selector) // Error selector
        //     )
        // );
        // vm.expectRevert(
        //     abi.encodeWithSignature(
        //         "Wrap__HookCallFailed(address,bytes)",
        //         address(hook),
        //         abi.encodeWithSelector(CoPoolHook.InvalidTokenSelection.selector)
        //     )
        // );
        // TODO: No idea how to isolate this to the selector.
        // Everything seems outdated: https://www.quicknode.com/guides/defi/dexs/how-to-create-uniswap-v4-hooks
        vm.expectRevert();
        // vm.expectRevert(
        //     abi.encodeWithSignature(
        //         "Wrap__FailedHookCall(address,bytes)",
        //         address(hook),
        //         abi.encodeWithSignature("Error(string)", CoPoolHook.InvalidTokenSelection.selector)
        //     )
        // );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(tokenId) // Arbitrary salt - however used in the protocol to identify the tokenId.
            }),
            hookData
        );
    }
    // Here we unapprove the token0 from the sender, and leverage the token0 in hook.

    function test_addDefaultLiquidity() public {
        // Start by bonding the bondToken

        // Approve and stake token1
        // MockERC20(Currency.unwrap(token0)).approve(address(hook), 10 ether);

        uint256 tokenId = 123;
        // This will single stake token0 and co-pool it against the token1 already deposited.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(tokenId) // Arbitrary salt - however used in the protocol to identify the tokenId.
            }),
            ZERO_BYTES
        );

        PoolId poolId = key.toId();
        // Check the poolManager's balance of token0
        uint256 liquidity = StateLibrary.getLiquidity(manager, poolId);
        // console.log("test_addSingleToken0Liquidity() - liquidity: ", liquidity);
        assertEq(liquidity, 1 ether);
    }

    function test_addSingleToken0Liquidity() public {
        // Start by bonding the bondToken

        // Approve and stake token1
        // MockERC20(Currency.unwrap(token0)).approve(address(hook), 10 ether);

        MockERC20(Currency.unwrap(token1)).approve(address(hook), 10 ether);
        // Unapprove token1 from swapRouter and modifyLiquidityRouter to prevent it from being staked.
        MockERC20(Currency.unwrap(token1)).approve(address(swapRouter), 0);
        MockERC20(Currency.unwrap(token1)).approve(address(modifyLiquidityRouter), 0);
        hook.deposit(10 ether, false);

        int256 deltaOfToken1 = hook.deltaOfToken1();
        console.log("test_addSingleToken0Liquidity() - Before modifyLiquidity - deltaOfToken1: ", deltaOfToken1);
        assertEq(deltaOfToken1, -10 ether);

        bytes memory action = hook.COPOOL();
        uint8 tokenSelection = 0;

        bytes memory hookData = abi.encode(action, tokenSelection);

        PoolId poolId = key.toId();
        uint256 liquidityBefore = StateLibrary.getLiquidity(manager, poolId);

        uint256 tokenId = 123;
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: bytes32(tokenId) // Arbitrary salt - however used in the protocol to identify the tokenId.
        });
        // This will single stake token0 and co-pool it against the token1 already deposited.
        modifyLiquidityRouter.modifyLiquidity(key, params, hookData);

        // Check the poolManager's balance of token0
        uint256 liquidityAfter = StateLibrary.getLiquidity(manager, poolId);
        console.log("test_addSingleToken0Liquidity() - liquidityAfter: ", liquidityAfter);
        assertEq(liquidityAfter, 1 ether);

        // Check the hook's delta of token0
        int256 deltaOfToken0 = hook.deltaOfToken0();
        console.log("test_addSingleToken0Liquidity() - deltaOfToken0: ", deltaOfToken0);
        assertEq(deltaOfToken0, 0);

        (, int24 tick,,) = StateLibrary.getSlot0(manager, poolId);
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tick + params.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tick + params.tickUpper);
        (uint256 beforeAmount0, uint256 beforeAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, uint128(liquidityBefore)
        );
        (uint256 afterAmount0, uint256 afterAmount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceAX96, sqrtPriceBX96, uint128(liquidityAfter));

        uint256 diffInAmount1 = afterAmount1 - beforeAmount1;
        console.log("test_addSingleToken0Liquidity() - diffInAmount1: ", diffInAmount1);

        int256 newDeltaOfToken1 = hook.deltaOfToken1();
        console.log("test_addSingleToken0Liquidity() - After modifyLiquidity - newDeltaOfToken1: ", newDeltaOfToken1);
        assertEq(newDeltaOfToken1, -int256(10 ether) + int256(diffInAmount1));
    }
}
