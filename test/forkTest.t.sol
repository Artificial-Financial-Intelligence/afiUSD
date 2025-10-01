// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IafiToken, IManager, IYield} from "./mock/interfaces.sol";
import {console2} from "forge-std/console2.sol";
import {afiToken} from "../src/afiToken.sol";

contract forkTest is Test {
    IYield yield = IYield(0xb82b080791dFA4aa6Cac8c3f9c0fcb4471C9FEaD);
    IafiToken afiUSD = IafiToken(0x0B4C655bC989baaFe728f8270ff988A7C2B40Fd1);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IManager manager = IManager(0xDe9E75891f4c206B7A0477C683e78d2344920a4C);

    address admin = 0xfa5b3614A7C8265E3e8c4f56bC123203BD155ff2;
    address operator = 0x30262F5b369AB2d548a2aDfbC0A69ab6A17a00D0;
    address rebalancer = 0xa09B31a5E092708A844bdBCB414d1C7Ab9e8E6De;

    address user1 = vm.addr(0x1);
    address user2 = vm.addr(0x2);
    address user3 = vm.addr(0x3);
    address minter = vm.addr(0x4);

    function setUp() public {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/sKwwBtEcY__mxUnoLrICC", 23198600);
        deal(address(usdc), user1, 100e6);
        deal(address(usdc), user2, 150e6);
        deal(address(usdc), user3, 500e6);
        deal(address(usdc), address(minter), 200000e6);
    }

    function _logSection(string memory title) internal pure {
        console2.log("");
        console2.log("=== ", title, " ===");
    }

    function testYieldETH() public {
        uint256 amountToDistribute = 59608876;
        uint256 feeAmount = 10259680;
        
        vm.prank(rebalancer);
        yield.distributeYield(amountToDistribute, feeAmount, 1, true);

        uint256 vestingTime = afiUSD.vestingPeriod();
        uint256 partVestingTime = vestingTime / 10;

        // Log initial state
        _logYieldState("Initial");

        // Test vesting progression in 10 steps
        for (uint256 i = 1; i <= 10; i++) {
            vm.warp(block.timestamp + partVestingTime);
            _logYieldState(string(abi.encodePacked("Step ", vm.toString(i))));
        }
    }

    function _logYieldState(string memory step) internal view {
        console2.log(block.timestamp, afiUSD.exchangeRate(),afiUSD.getUnvestedAmount(),  afiUSD.totalAssets());
    }

    function testchange() public {
        vm.startPrank(admin);
        afiUSD.setVestingPeriod(86400);
        yield.setMinDistributionInterval(86400);
        vm.stopPrank();

        afiUSD.exchangeRate();
        afiUSD.getUnvestedAmount();
        afiUSD.totalAssets();
        afiUSD.totalSupply();
        afiUSD.virtualAssets();
        afiUSD.totalRequestedAmount();
        afiUSD.fee();
        afiUSD.vestingAmount();
        afiUSD.vestingPeriod();
    }

    function _logUserDeposit(address user, uint256 usdcAmount, uint256 afiAmount) internal pure {
        string memory message = string(
            abi.encodePacked(
                "User ",
                vm.toString(user),
                " deposited ",
                vm.toString(usdcAmount / 1e6),
                " USDC -> ",
                vm.toString(afiAmount / 1e18),
                " afiUSD"
            )
        );
        console2.log(message);
    }

    function _logUserRedemption(address user, uint256 afiAmount, uint256 usdcReceived) internal pure {
        string memory message = string(
            abi.encodePacked(
                "User ",
                vm.toString(user),
                " redeemed ",
                vm.toString(afiAmount / 1e18),
                " afiUSD -> ",
                vm.toString(usdcReceived / 1e6),
                " USDC"
            )
        );
        console2.log(message);
    }

    function _logSystemState() internal view {
        console2.log("Total Supply:", afiUSD.totalSupply() / 1e18, "afiUSD");
        console2.log("Exchange Rate:", afiUSD.exchangeRate());
        console2.log("Total Requested:", afiUSD.totalRequestedAmount() / 1e18, "afiUSD");
    }

    function _deposit(address user, uint256 usdcAmount) internal returns (uint256) {
        vm.startPrank(user);
        IERC20(address(usdc)).approve(address(afiUSD), usdcAmount);
        uint256 balanceBefore = afiUSD.balanceOf(user);
        afiUSD.deposit(usdcAmount, user);
        uint256 balanceAfter = afiUSD.balanceOf(user);
        vm.stopPrank();
        return balanceAfter - balanceBefore;
    }

    function _requestRedeem(address user, uint256 afiAmount) internal {
        vm.startPrank(user);
        afiUSD.requestRedeem(afiAmount);
        vm.stopPrank();
        vm.startPrank(address(operator));
        manager.transferToVault(address(usdc), afiUSD.totalRequestedAmount());
        vm.stopPrank();
    }

    function _distributeYield(uint256 amount, uint256 epoch) internal {
        console2.log("Manager USDC balance before yield:", usdc.balanceOf(address(manager)) / 1e6);
        vm.prank(rebalancer);
        yield.distributeYield(amount, 0, epoch, true);

        vm.startPrank(address(minter));
        usdc.transfer(address(manager), amount);
        vm.stopPrank();
        console2.log("Yield distributed:", amount / 1e6, "USDC");
    }

    function test_basic_deposit_redeem() public {
        _logSection("Basic Deposit & Redemption Test");

        uint256 afiReceived = _deposit(user1, 100e6);
        _logUserDeposit(user1, 100e6, afiReceived);
        _logSystemState();

        _requestRedeem(user1, 50e18);
        console2.log("User1 requested redemption of 50 afiUSD");

        vm.warp(block.timestamp + 2 days);

        vm.prank(user1);
        afiUSD.redeem(50e18, user1, user1);
        _logUserRedemption(user1, 50e18, usdc.balanceOf(user1));

        assertEq(afiUSD.balanceOf(user1), 50e18);
        assertEq(usdc.balanceOf(user1), 50e6);

        _logSection("Test Completed");
    }

    function test_yield_before_vesting() public {
        _logSection("Yield Before Vesting Test");

        _deposit(user1, 100e6);
        console2.log("Initial exchange rate:", afiUSD.exchangeRate());

        _distributeYield(50e6, 1);
        console2.log("Yield distributed: 50 USDC");

        vm.warp(block.timestamp + 12 hours);
        console2.log("Exchange rate after 12h:", afiUSD.exchangeRate());

        _requestRedeem(user1, 100e18);
        vm.warp(block.timestamp + 2 days);

        vm.prank(user1);
        afiUSD.redeem(100e18, user1, user1);
        _logUserRedemption(user1, 100e18, usdc.balanceOf(user1));

        assertEq(afiUSD.balanceOf(user1), 0);
        assertGt(usdc.balanceOf(user1), 100e6);

        _logSection("Test Completed");
    }

    function test_yield_fully_vested() public {
        _logSection("Yield Fully Vested Test");

        _deposit(user1, 100e6);
        console2.log("Initial exchange rate:", afiUSD.exchangeRate());

        _distributeYield(50e6, 1);
        vm.warp(block.timestamp + 24 hours);
        console2.log("Exchange rate after 24h:", afiUSD.exchangeRate());

        _requestRedeem(user1, 100e18);
        vm.warp(block.timestamp + 2 days);

        vm.prank(user1);
        afiUSD.redeem(100e18, user1, user1);
        _logUserRedemption(user1, 100e18, usdc.balanceOf(user1));

        assertEq(afiUSD.balanceOf(user1), 0);
        assertGt(usdc.balanceOf(user1), 100e6);

        _logSection("Test Completed");
    }

    function test_multi_user_interaction() public {
        _logSection("Multi-User Interaction Test");

        uint256 afi1 = _deposit(user1, 100e6);
        uint256 afi2 = _deposit(user2, 150e6);
        uint256 afi3 = _deposit(user3, 200e6);

        _logUserDeposit(user1, 100e6, afi1);
        _logUserDeposit(user2, 150e6, afi2);
        _logUserDeposit(user3, 200e6, afi3);
        _logSystemState();

        _distributeYield(50e6, 1);
        vm.warp(block.timestamp + 24 hours);
        console2.log("Exchange rate after yield:", afiUSD.exchangeRate());

        _requestRedeem(user1, 50e18);
        _requestRedeem(user2, 75e18);
        console2.log("Redemption requests submitted");
        _logSystemState();
        vm.warp(block.timestamp + 2 days);
        uint256 additionalAfi = _deposit(user3, 100e6);
        uint256 user3BalanceAfter = afiUSD.balanceOf(user3);

        string memory message = string(
            abi.encodePacked("User3 additional deposit: 100 USDC -> ", vm.toString(additionalAfi / 1e18), " afiUSD")
        );
        console2.log(message);
        console2.log("User3 total balance:", user3BalanceAfter / 1e18, "afiUSD");

        _distributeYield(50e6, 2);
        vm.warp(block.timestamp + 3 days);
        _logSystemState();
        vm.prank(user1);
        afiUSD.redeem(50e18, user1, user1);
        vm.prank(user2);
        afiUSD.redeem(75e18, user2, user2);
        _logSection("Final Balances");
        string memory message1 = string(
            abi.encodePacked(
                "User1: ",
                vm.toString(afiUSD.balanceOf(user1) / 1e18),
                " afiUSD + ",
                vm.toString(usdc.balanceOf(user1) / 1e6),
                " USDC"
            )
        );
        console2.log(message1);
        string memory message2 = string(
            abi.encodePacked(
                "User2: ",
                vm.toString(afiUSD.balanceOf(user2) / 1e18),
                " afiUSD + ",
                vm.toString(usdc.balanceOf(user2) / 1e6),
                " USDC"
            )
        );
        console2.log(message2);
        console2.log("User3:", afiUSD.balanceOf(user3) / 1e18, "afiUSD");
        console2.log("user3 preview redeem:", afiUSD.previewRedeem(afiUSD.balanceOf(user3)));

        uint256 expectedUser3Balance = 200e18 + additionalAfi;
        assertEq(afiUSD.balanceOf(user3), expectedUser3Balance);
        assertGt(afiUSD.exchangeRate(), 1e6);

        _logSection("Test Completed");
    }

    function test_yield_multiple_epochs() public {
        _logSection("Multiple Yield Epochs Test");

        _deposit(user1, 100e6);
        _deposit(user2, 100e6);
        console2.log("Initial exchange rate:", afiUSD.exchangeRate());

        _distributeYield(50e6, 1);
        vm.warp(block.timestamp + 1 days);
        console2.log("After epoch 1:", afiUSD.exchangeRate());

        _distributeYield(30e6, 2);
        vm.warp(block.timestamp + 2 days);
        console2.log("After epoch 2:", afiUSD.exchangeRate());

        _distributeYield(20e6, 3);
        vm.warp(block.timestamp + 3 days);
        console2.log("After epoch 3:", afiUSD.exchangeRate());

        _requestRedeem(user1, 100e18);
        vm.warp(block.timestamp + 4 days);

        vm.prank(user1);
        afiUSD.redeem(100e18, user1, user1);
        _logUserRedemption(user1, 100e18, usdc.balanceOf(user1));

        assertGt(usdc.balanceOf(user1), 100e6);
        console2.log("Total yield accumulated:", (usdc.balanceOf(user1) - 100e6) / 1e6, "USDC");

        _logSection("Test Completed");
    }

    function test_multiple_redeem_requests() public {
        _logSection("Multiple Redeem Requests Test");

        _deposit(user1, 100e6);
        _deposit(user2, 100e6);
        _logSystemState();

        _requestRedeem(user1, 50e18);
        vm.expectRevert();
        _requestRedeem(user1, 1e18);

        (uint256 shares, uint256 assets, uint256 timestamp, bool exists) = afiUSD.redemptionRequests(user1);
        console2.log("Shares:", shares);
        console2.log("Assets:", assets);
        console2.log("Timestamp:", timestamp);
        console2.log("Exists:", exists);

        _logSection("Test Completed");
    }

    function test_upgrade_afiToken() public {
        _deposit(user2, 100e6);

        // Capture all important state variables BEFORE upgrade
        console2.log("=== STORAGE STATE BEFORE UPGRADE ===");

        // Basic token state
        uint256 totalSupplyBefore = afiUSD.totalSupply();
        uint256 exchangeRateBefore = afiUSD.exchangeRate();
        uint256 exchangeRateScaledBefore = afiUSD.exchangeRateScaled();
        uint256 totalRequestedAmountBefore = afiUSD.totalRequestedAmount();
        uint256 feeBefore = afiUSD.fee();

        // User balances and state
        uint256 user2BalanceBefore = afiUSD.balanceOf(user2);
        uint256 user2AllowanceBefore = usdc.allowance(user2, address(afiUSD));

        // System configuration
        address managerBefore = afiUSD.manager();
        uint256 cooldownPeriodBefore = afiUSD.cooldownPeriod();
        uint256 vestingPeriodBefore = afiUSD.vestingPeriod();
        uint256 lastDistributionTimestampBefore = afiUSD.lastDistributionTimestamp();
        uint256 vestingAmountBefore = afiUSD.vestingAmount();
        uint256 virtualAssetsBefore = afiUSD.virtualAssets();

        // Pause state
        bool pausedBefore = afiUSD.paused();

        // Access control
        bool adminRoleBefore = afiUSD.hasRole(afiUSD.ADMIN_ROLE(), admin);
        bool defaultAdminRoleBefore = afiUSD.hasRole(afiUSD.DEFAULT_ADMIN_ROLE(), admin);

        console2.log("Total Supply:", totalSupplyBefore / 1e18, "afiUSD");
        console2.log("Exchange Rate:", exchangeRateBefore);
        console2.log("Exchange Rate Scaled:", exchangeRateScaledBefore);
        console2.log("Total Requested Amount:", totalRequestedAmountBefore / 1e18, "afiUSD");
        console2.log("Fee:", feeBefore);
        console2.log("User2 Balance:", user2BalanceBefore / 1e18, "afiUSD");
        console2.log("Manager:", managerBefore);
        console2.log("Cooldown Period:", cooldownPeriodBefore);
        console2.log("Vesting Period:", vestingPeriodBefore);
        console2.log("Last Distribution Timestamp:", lastDistributionTimestampBefore);
        console2.log("Vesting Amount:", vestingAmountBefore / 1e18, "afiUSD");
        console2.log("Virtual Assets:", virtualAssetsBefore / 1e18, "afiUSD");
        console2.log("Paused:", pausedBefore);
        console2.log("Admin Role:", adminRoleBefore);
        console2.log("Default Admin Role:", defaultAdminRoleBefore);

        afiToken newImplementation = new afiToken();
        console2.log("New implementation deployed at:", address(newImplementation));

        // Perform upgrade
        vm.startPrank(admin);
        afiUSD.upgradeToAndCall(address(newImplementation), "");
        console2.log("Upgrade completed");
        vm.stopPrank();

        // Capture all important state variables AFTER upgrade
        console2.log("=== STORAGE STATE AFTER UPGRADE ===");

        // Basic token state
        uint256 totalSupplyAfter = afiUSD.totalSupply();
        uint256 exchangeRateAfter = afiUSD.exchangeRate();
        uint256 exchangeRateScaledAfter = afiUSD.exchangeRateScaled();
        uint256 totalRequestedAmountAfter = afiUSD.totalRequestedAmount();
        uint256 feeAfter = afiUSD.fee();

        // User balances and state
        uint256 user2BalanceAfter = afiUSD.balanceOf(user2);
        uint256 user2AllowanceAfter = usdc.allowance(user2, address(afiUSD));

        // System configuration
        address managerAfter = afiUSD.manager();
        uint256 cooldownPeriodAfter = afiUSD.cooldownPeriod();
        uint256 vestingPeriodAfter = afiUSD.vestingPeriod();
        uint256 lastDistributionTimestampAfter = afiUSD.lastDistributionTimestamp();
        uint256 vestingAmountAfter = afiUSD.vestingAmount();
        uint256 virtualAssetsAfter = afiUSD.virtualAssets();

        // Pause state
        bool pausedAfter = afiUSD.paused();

        // Access control
        bool adminRoleAfter = afiUSD.hasRole(afiUSD.ADMIN_ROLE(), admin);
        bool defaultAdminRoleAfter = afiUSD.hasRole(afiUSD.DEFAULT_ADMIN_ROLE(), admin);

        console2.log("Total Supply:", totalSupplyAfter / 1e18, "afiUSD");
        console2.log("Exchange Rate:", exchangeRateAfter);
        console2.log("Exchange Rate Scaled:", exchangeRateScaledAfter);
        console2.log("Total Requested Amount:", totalRequestedAmountAfter / 1e18, "afiUSD");
        console2.log("Fee:", feeAfter);
        console2.log("User2 Balance:", user2BalanceAfter / 1e18, "afiUSD");
        console2.log("Manager:", managerAfter);
        console2.log("Cooldown Period:", cooldownPeriodAfter);
        console2.log("Vesting Period:", vestingPeriodAfter);
        console2.log("Last Distribution Timestamp:", lastDistributionTimestampAfter);
        console2.log("Vesting Amount:", vestingAmountAfter / 1e18, "afiUSD");
        console2.log("Virtual Assets:", virtualAssetsAfter / 1e18, "afiUSD");
        console2.log("Paused:", pausedAfter);
        console2.log("Admin Role:", adminRoleAfter);
        console2.log("Default Admin Role:", defaultAdminRoleAfter);

        // Verify all storage values remain unchanged
        console2.log("=== STORAGE CONSISTENCY VERIFICATION ===");

        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply changed after upgrade");
        assertEq(exchangeRateAfter, exchangeRateBefore, "Exchange rate changed after upgrade");
        assertEq(exchangeRateScaledAfter, exchangeRateScaledBefore, "Exchange rate scaled changed after upgrade");
        assertEq(totalRequestedAmountAfter, totalRequestedAmountBefore, "Total requested amount changed after upgrade");
        assertEq(feeAfter, feeBefore, "Fee changed after upgrade");
        assertEq(user2BalanceAfter, user2BalanceBefore, "User2 balance changed after upgrade");
        assertEq(user2AllowanceAfter, user2AllowanceBefore, "User2 allowance changed after upgrade");
        assertEq(managerAfter, managerBefore, "Manager address changed after upgrade");
        assertEq(cooldownPeriodAfter, cooldownPeriodBefore, "Cooldown period changed after upgrade");
        assertEq(vestingPeriodAfter, vestingPeriodBefore, "Vesting period changed after upgrade");
        assertEq(
            lastDistributionTimestampAfter,
            lastDistributionTimestampBefore,
            "Last distribution timestamp changed after upgrade"
        );
        assertEq(vestingAmountAfter, vestingAmountBefore, "Vesting amount changed after upgrade");
        assertEq(virtualAssetsAfter, virtualAssetsBefore, "Virtual assets changed after upgrade");
        assertEq(pausedAfter, pausedBefore, "Pause state changed after upgrade");
        assertEq(adminRoleAfter, adminRoleBefore, "Admin role changed after upgrade");
        assertEq(defaultAdminRoleAfter, defaultAdminRoleBefore, "Default admin role changed after upgrade");

        console2.log("All storage values verified - no changes detected");

        // Test that functionality still works after upgrade
        console2.log("=== FUNCTIONALITY TEST AFTER UPGRADE ===");

        _requestRedeem(user2, 25e18);
        vm.expectRevert();
        _requestRedeem(user2, 5e18);
        console2.log("Redemption request submitted after upgrade");

        (uint256 shares2, uint256 assets2, uint256 timestamp2, bool exists2) = afiUSD.redemptionRequests(user2);
        console2.log("User2 redemption request - Shares:", shares2, assets2, exists2);
        vm.warp(block.timestamp + 2 days);
        vm.prank(user2);
        afiUSD.redeem(25e18, user2, user2);
        _logUserRedemption(user2, 25e18, usdc.balanceOf(user2));

        _logSystemState();

        _logSection("Upgrade Test Completed - All Storage Verified");
    }
}
