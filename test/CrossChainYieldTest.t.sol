// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {afiToken} from "../src/afiToken.sol";
import {Manager} from "../src/Manager.sol";
import {Yield} from "../src/Yield.sol";
import {afiProxy} from "../src/Proxy.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract CrossChainYieldTest is Test {
    address admin = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address treasury = address(4);
    address yieldRebalancer = address(5);
    address operator = address(6);
    uint256 cooldownPeriod = 24 hours;
    uint256 vestingPeriod = 1 days;
    MockERC20 asset;

    function calculateGlobalYield(uint256 ethDeposit, uint256 KATANADeposit, uint256 ethYield, uint256 KATANAYield)
        internal
        pure
        returns (uint256 ethVaultYield, uint256 KATANAVaultYield, uint256 newExchangeRate)
    {
        uint256 totalDeposit = ethDeposit + KATANADeposit;
        uint256 totalYield = ethYield + KATANAYield;
        // global yield per share (in 6 decimals)
        // newExchangeRate = (totalDeposit + totalYield) / totalDeposit * 1e6
        // But since deposits are in 6 decimals, exchange rate is also in 6 decimals
        newExchangeRate = ((totalDeposit + totalYield) * 1e6) / totalDeposit;
        ethVaultYield = (newExchangeRate * ethDeposit) / 1e6 - ethDeposit;
        KATANAVaultYield = (newExchangeRate * KATANADeposit) / 1e6 - KATANADeposit;
    }

    function test_DailyYieldDistribution() public {
        asset = new MockERC20("USD Coin", "USDC");
        uint256 ethDeposit = 500_000e6;
        uint256 KATANADeposit = 300_000e6;
        uint256 ethYield = 2400e6;
        uint256 KATANAYield = 1300e6;
        asset.mint(user1, ethDeposit);
        asset.mint(user2, KATANADeposit);

        // Deploy and setup ETH vault
        Manager mETHImpl = new Manager();
        Yield yETHImpl = new Yield();
        afiToken vETHImpl = new afiToken();

        // Deploy proxies without initialization data
        afiProxy mETHProxy = new afiProxy(address(mETHImpl), "");
        afiProxy yETHProxy = new afiProxy(address(yETHImpl), "");
        afiProxy vETHProxy = new afiProxy(address(vETHImpl), "");

        // Cast proxies to their respective interfaces
        Manager mETH = Manager(address(mETHProxy));
        Yield yETH = Yield(address(yETHProxy));
        afiToken vETH = afiToken(address(vETHProxy));

        // Initialize contracts with proper addresses
        mETH.initialize(admin, address(yETH), operator);
        yETH.initialize(admin, yieldRebalancer);
        vETH.initialize("afiUSD ETH", "afiUSD-ETH", IERC20(asset), admin, address(mETH), cooldownPeriod, vestingPeriod);

        vm.startPrank(admin);
        mETH.setTreasury(treasury);
        yETH.setManager(address(mETH));
        mETH.setManagerAndYield(address(yETH), address(vETH));
        mETH.setMinSharesInVaultToken(address(vETH), 1);
        vm.stopPrank();

        // Deploy and setup KATANA vault
        Manager mKATANAImpl = new Manager();
        Yield yKATANAImpl = new Yield();
        afiToken vKATANAImpl = new afiToken();

        // Deploy proxies for KATANA without initialization data
        afiProxy mKATANAProxy = new afiProxy(address(mKATANAImpl), "");
        afiProxy yKATANAProxy = new afiProxy(address(yKATANAImpl), "");
        afiProxy vKATANAProxy = new afiProxy(address(vKATANAImpl), "");

        // Cast proxies to their respective interfaces
        Manager mKATANA = Manager(address(mKATANAProxy));
        Yield yKATANA = Yield(address(yKATANAProxy));
        afiToken vKATANA = afiToken(address(vKATANAProxy));

        // Initialize contracts with proper addresses
        mKATANA.initialize(admin, address(yKATANA), operator);
        yKATANA.initialize(admin, yieldRebalancer);
        vKATANA.initialize(
            "afiUSD KATANA", "afiUSD-KATANA", IERC20(asset), admin, address(mKATANA), cooldownPeriod, vestingPeriod
        );

        vm.startPrank(admin);
        mKATANA.setTreasury(treasury);
        yKATANA.setManager(address(mKATANA));
        mKATANA.setManagerAndYield(address(yKATANA), address(vKATANA));
        mKATANA.setMinSharesInVaultToken(address(vKATANA), 1);
        vm.stopPrank();

        // Deposit
        vm.startPrank(user1);
        asset.approve(address(vETH), ethDeposit);
        vETH.deposit(ethDeposit, user1);
        vm.stopPrank();
        vm.startPrank(user2);
        asset.approve(address(vKATANA), KATANADeposit);
        vKATANA.deposit(KATANADeposit, user2);
        vm.stopPrank();

        // Log initial state
        console2.log("--- Initial State ---");
        console2.log("ETH Deposit:", ethDeposit / 1e6, "USD");
        console2.log("KATANA Deposit:", KATANADeposit / 1e6, "USD");
        console2.log("ETH Yield (Original):", ethYield / 1e6, "USD");
        console2.log("KATANA Yield (Original):", KATANAYield / 1e6, "USD");
        console2.log("ETH Daily Yield (raw):", ethYield / 1e6, "USD");
        console2.log("KATANA Daily Yield (raw):", KATANAYield / 1e6, "USD");

        console2.log("User1 Shares (ETH):", vETH.balanceOf(user1));
        console2.log("User2 Shares (KATANA):", vKATANA.balanceOf(user2));
        console2.log("ETH Exchange Rate (before):", vETH.exchangeRate());
        console2.log("KATANA Exchange Rate (before):", vKATANA.exchangeRate());
        uint256 user1AssetsBefore = vETH.previewRedeem(vETH.balanceOf(user1));
        uint256 user2AssetsBefore = vKATANA.previewRedeem(vKATANA.balanceOf(user2));
        console2.log("User1 Assets Before Yield:", user1AssetsBefore / 1e6, "USD");
        console2.log("User2 Assets Before Yield:", user2AssetsBefore / 1e6, "USD");

        // Calculate global yield for both vaults
        (uint256 ethVaultYield, uint256 KATANAVaultYield, uint256 newExchangeRate) =
            calculateGlobalYield(ethDeposit, KATANADeposit, ethYield, KATANAYield);
        console2.log("\n--- Global Yield Calculation ---");
        console2.log("Global New Exchange Rate:", newExchangeRate);
        console2.log("ETH Vault Yield to Distribute:", ethVaultYield / 1e6, "USD");
        console2.log("KATANA Vault Yield to Distribute:", KATANAVaultYield / 1e6, "USD");
        console2.log("Total Yield Distributed:", (ethVaultYield + KATANAVaultYield) / 1e6, "USD");

        // Distribute global yield
        vm.startPrank(yieldRebalancer);
        yETH.distributeYield(ethVaultYield, 0, yETH.getEpoch() + 1, true);
        yKATANA.distributeYield(KATANAVaultYield, 0, yKATANA.getEpoch() + 1, true);
        vm.stopPrank();
        vm.warp(block.timestamp + vETH.vestingPeriod() + 1);

        // Log after yield
        uint256 ethRate = vETH.exchangeRate();
        uint256 KATANARate = vKATANA.exchangeRate();
        console2.log("\n--- After Global Yield Distribution & Vesting ---");
        console2.log("ETH Exchange Rate (after):", ethRate);
        console2.log("KATANA Exchange Rate (after):", KATANARate);
        uint256 user1AssetsAfter = vETH.previewRedeem(vETH.balanceOf(user1));
        uint256 user2AssetsAfter = vKATANA.previewRedeem(vKATANA.balanceOf(user2));
        console2.log("User1 Assets After Yield:", user1AssetsAfter / 1e6, "USD");
        console2.log("User2 Assets After Yield:", user2AssetsAfter / 1e6, "USD");
        assertApproxEqAbs(ethRate, KATANARate, 1, "Exchange rates should be equal after yield distribution");
    }
}
