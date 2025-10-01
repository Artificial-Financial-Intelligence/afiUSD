// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {afiToken} from "../src/afiToken.sol";
import {Manager} from "../src/Manager.sol";
import {Yield} from "../src/Yield.sol";
import {afiProxy} from "../src/Proxy.sol";
import {IManager, ManageAssetAndShares} from "../src/Interface/IManager.sol";

contract IntegrationTest is Test {
    MockERC20 public asset;
    afiToken public vault;
    Manager public manager;
    Yield public yield;

    address public admin = address(0x1);
    address public treasury = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x13);
    address public rebalancer = address(0x5);
    address public yieldRebalancer = address(0x6);
    address public executor = address(0x7);

    uint256 public constant INITIAL_BALANCE = 10000e6;
    uint256 public constant DEPOSIT_AMOUNT = 1000e6;
    uint256 public constant WITHDRAWAL_AMOUNT = 1000e6;
    uint256 public constant YIELD_AMOUNT = 5e6;
    uint256 public constant FEE_AMOUNT = 2e6;
    uint256 public cooldownPeriod = 24 hours;
    uint256 public vestingPeriod = 1 days;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event DistributeYield(address caller, address indexed asset, address indexed receiver, uint256 amount, bool profit);
    event TransferRewards(address indexed caller, uint256 amount);
    event RedemptionRequested(address indexed user, uint256 shares, uint256 timestamp);
    event WithdrawalExecuted(address indexed user, uint256 shares, uint256 assets);

    function setUp() public {
        vm.startPrank(admin);

        asset = new MockERC20("USDC", "USDC");

        // Deploy implementation contracts
        afiToken afiTokenImpl = new afiToken();
        Manager managerImpl = new Manager();
        Yield yieldImpl = new Yield();

        // Deploy Yield proxy using UUPS pattern
        bytes memory yieldInitData = abi.encodeWithSelector(
            Yield.initialize.selector,
            admin, // admin
            yieldRebalancer // rebalancer
        );

        afiProxy yieldProxy = new afiProxy(address(yieldImpl), yieldInitData);
        yield = Yield(address(yieldProxy));

        // Deploy Manager proxy using UUPS pattern
        bytes memory managerInitData = abi.encodeWithSelector(
            Manager.initialize.selector,
            admin, // admin
            address(yield), // yield
            executor // executor
        );

        afiProxy managerProxy = new afiProxy(address(managerImpl), managerInitData);
        manager = Manager(address(managerProxy));

        // Deploy afiToken proxy using UUPS pattern
        bytes memory afiTokenInitData = abi.encodeWithSelector(
            afiToken.initialize.selector,
            "Artificial Financial Intelligence USD",
            "afiUSD",
            IERC20(asset), // asset
            admin, // admin
            address(manager), // manager
            cooldownPeriod, // cooldownPeriod
            vestingPeriod // vestingPeriod
        );

        afiProxy vaultProxy = new afiProxy(address(afiTokenImpl), afiTokenInitData);
        vault = afiToken(address(vaultProxy));

        vm.stopPrank();

        vm.startPrank(admin);
        manager.setTreasury(treasury);
        manager.setManagerAndYield(address(yield), address(vault));
        manager.setMinSharesInVaultToken(address(vault), 1e6);
        manager.setWhitelistedAddresses(new address[](0), new bool[](0));
        manager.setMaxRedeemCap(address(vault), type(uint256).max);

        yield.setManager(address(manager));
        yield.grantRole(yield.REBALANCER_ROLE(), yieldRebalancer);
        yield.grantRole(yield.REBALANCER_ROLE(), rebalancer);
        yield.setMinDistributionInterval(24 hours - 1);
        vm.stopPrank();

        asset.mint(user1, INITIAL_BALANCE);
        asset.mint(user2, INITIAL_BALANCE);
        asset.mint(treasury, INITIAL_BALANCE);
        asset.mint(address(manager), INITIAL_BALANCE * 2);
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _transferAssetsToVault(uint256 amount) internal {
        vm.startPrank(address(manager));
        asset.transfer(address(vault), amount);
        vm.stopPrank();
    }

    function _distributeYieldWithAssets(uint256 yieldAmount, uint256 feeAmount, uint256 nonce, bool isProfit)
        internal
    {
        console2.log("Distributing yield (1e18):", yieldAmount);
        console2.log("Fee amount (1e18):", feeAmount);
        console2.log("Is profit:", isProfit);
        if (isProfit) {
            vm.startPrank(admin);
            asset.mint(address(vault), yieldAmount / 1e12);
            vm.stopPrank();
        } else {
            vm.startPrank(address(manager));
            asset.transfer(address(vault), DEPOSIT_AMOUNT);
            vm.stopPrank();
        }
        vm.startPrank(yieldRebalancer);
        yield.distributeYield(yieldAmount, feeAmount, nonce, isProfit);
        vm.stopPrank();
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        console2.log("Vault total assets after yield:", vault.totalAssets());
    }

    function scaledownDecimal(uint256 amount, uint256 decimals) public pure returns (uint256) {
        return amount / (10 ** (18 - decimals));
    }

    function test_MultipleUsers_DepositWithYieldDistribution() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT * 2, user2);
        vm.stopPrank();
        uint256 totalAssetsBeforeYield = vault.totalAssets();
        uint256 user1SharesBefore = vault.balanceOf(user1);
        uint256 user2SharesBefore = vault.balanceOf(user2);
        _distributeYieldWithAssets(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        uint256 totalAssetsAfterYield = vault.totalAssets();
        assertGe(totalAssetsAfterYield, totalAssetsBeforeYield, "Total assets should not decrease");
        uint256 user1SharesAfter = vault.balanceOf(user1);
        uint256 user2SharesAfter = vault.balanceOf(user2);
        assertEq(user1SharesAfter, user1SharesBefore, "User1 shares should remain same");
        assertEq(user2SharesAfter, user2SharesBefore, "User2 shares should remain same");
        uint256 exchangeRate = vault.exchangeRate();
        assertGe(exchangeRate, 1e6, "Exchange rate should not decrease");
    }

    function test_YieldDistribution_ProfitAndLoss() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
        uint256 initialAssets = vault.totalAssets();

        _distributeYieldWithAssets(YIELD_AMOUNT, FEE_AMOUNT, 1, true);

        uint256 assetsAfterProfit = vault.totalAssets();
        assertGe(assetsAfterProfit, initialAssets, "Assets should not decrease after profit");

        vm.warp(block.timestamp + 24 hours);
        _distributeYieldWithAssets(YIELD_AMOUNT / 2, FEE_AMOUNT / 2, 2, false);

        uint256 assetsAfterLoss = vault.totalAssets();
        assertLe(assetsAfterLoss, assetsAfterProfit, "Assets should not increase after loss");
        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(user1);
        vault.requestRedeem(vault.balanceOf(user1));
        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vault.redeem(requestShares, user1, user1);
        vm.stopPrank();
    }

    function test_WithdrawalFlow_RequestExecute() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 userShares = vault.balanceOf(user1);

        // Request redemption - shares should be burned immediately
        vault.requestRedeem(userShares);

        // Check that shares are burned
        assertEq(vault.balanceOf(user1), 0, "Shares should be burned immediately on request");

        (uint256 shares,,, bool exists) = vault.getRedeemRequest(user1);
        assertEq(shares, userShares, "Redemption request shares should match");
        assertTrue(exists, "Redemption request should exist");

        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);

        assertTrue(vault.canExecuteRedeem(user1), "Should be able to execute redemption");

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        vm.startPrank(user1);
        uint256 assetsBefore = asset.balanceOf(user1);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vault.redeem(requestShares, user1, user1);
        uint256 assetsAfter = asset.balanceOf(user1);

        assertGe(assetsAfter, assetsBefore, "Should receive assets after redemption");

        vm.stopPrank();
    }

    function test_RedeemFor_ExecutorExecution() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 userShares = vault.balanceOf(user1);
        console2.log("user Shares", vault.balanceOf(user1));

        // Request redemption - shares should be burned immediately
        vault.requestRedeem(userShares);

        (uint256 sharess,,,) = vault.getRedeemRequest(user1);
        console2.log("user  Request", sharess);
        console2.log("user ", vault.previewRedeem(sharess));

        // Check that shares are burned
        assertEq(vault.balanceOf(user1), 0, "Shares should be burned immediately on request");
        vm.stopPrank();

        // vm.warp(block.timestamp + vault.cooldownPeriod() + 1);

        vm.startPrank(address(manager));
        asset.transfer(address(vault), asset.balanceOf(address(manager)));
        vm.stopPrank();

        vm.startPrank(executor);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        manager.redeemFor(address(vault), user1);
        vm.stopPrank();

        (uint256 shares,,, bool exists) = vault.getRedeemRequest(user1);
        assertFalse(exists, "Redemption request should be removed after execution");
    }

    function test_Anyone_can_Withdraw() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        // Request redemption - shares should be burned immediately
        vault.requestRedeem(vault.balanceOf(user1));

        // Check that shares are burned
        assertEq(vault.balanceOf(user1), 0, "Shares should be burned immediately on request");

        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);
        uint256 before = asset.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        // this should not happen
        vm.startPrank(user3);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vm.expectRevert();
        vault.redeem(requestShares, user1, user1);
        uint256 afterBal = asset.balanceOf(user1);
        assertGe(afterBal, before, "Should not lose assets");
        vm.stopPrank();
    }

    function test_totalRequestedAmount() public {
        console2.log("=== Starting Clean test_totalRequestedAmount ===");
        console2.log("Initial DEPOSIT_AMOUNT:", DEPOSIT_AMOUNT);

        // Phase 1: Initial deposits
        console2.log("\n=== PHASE 1: Initial Deposits ===");

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        console2.log("User1 deposited:", DEPOSIT_AMOUNT);
        console2.log("User1 shares:", vault.balanceOf(user1));
        console2.log("Exchange rate:", vault.exchangeRate());
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());

        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT / 2, user2);
        console2.log("User2 deposited:", DEPOSIT_AMOUNT / 2);
        console2.log("User2 shares:", vault.balanceOf(user2));
        console2.log("Exchange rate:", vault.exchangeRate());
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());

        // Phase 2: Yield distribution
        console2.log("\n=== PHASE 2: Yield Distribution ===");

        _distributeYieldWithAssets(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        console2.log("Yield distributed:", YIELD_AMOUNT);

        vm.warp(block.timestamp + vault.vestingPeriod() + 1);

        console2.log("Exchange rate after yield:", vault.exchangeRate());
        console2.log("Total assets after yield:", vault.totalAssets());
        console2.log("Total shares after yield:", vault.totalSupply());
        console2.log("User1 shares after yield:", vault.balanceOf(user1));
        console2.log("User2 shares after yield:", vault.balanceOf(user2));

        // Phase 3: Redemption requests
        console2.log("\n=== PHASE 3: Redemption Requests ===");

        uint256 user1Shares = vault.balanceOf(user1);
        uint256 user2Shares = vault.balanceOf(user2);

        uint256 user1Assets = vault.previewRedeem(user1Shares);
        uint256 user2Assets = vault.previewRedeem(user2Shares);

        console2.log("User1 shares to redeem:", user1Shares);
        console2.log("User1 assets expected:", user1Assets);
        console2.log("User2 shares to redeem:", user2Shares);
        console2.log("User2 assets expected:", user2Assets);

        vm.prank(user1);
        vault.requestRedeem(user1Shares);
        console2.log("User1 requested redemption");
        console2.log("User1 remaining shares:", vault.balanceOf(user1));
        console2.log("Total assets after User1 request:", vault.totalAssets());
        console2.log("Total shares after User1 request:", vault.totalSupply());

        vm.prank(user2);
        vault.requestRedeem(user2Shares);
        console2.log("User2 requested redemption");
        console2.log("User2 remaining shares:", vault.balanceOf(user2));
        console2.log("Total assets after User2 request:", vault.totalAssets());
        console2.log("Total shares after User2 request:", vault.totalSupply());

        // Phase 4: Execute redemptions
        console2.log("\n=== PHASE 4: Execute Redemptions ===");

        uint256 totalRequested = vault.totalRequestedAmount();
        console2.log("Total requested amount:", totalRequested);

        // Transfer assets to vault
        vm.startPrank(address(manager));
        asset.transfer(address(vault), asset.balanceOf(address(manager)));
        vm.stopPrank();

        // Execute redemptions
        vm.startPrank(executor);
        console2.log("Executing User1 redemption...");
        manager.redeemFor(address(vault), user1);
        console2.log("User1 redemption completed");
        console2.log("Total requested amount after User1:", vault.totalRequestedAmount());
        console2.log("Total assets after User1:", vault.totalAssets());
        console2.log("Total shares after User1:", vault.totalSupply());

        console2.log("Executing User2 redemption...");
        manager.redeemFor(address(vault), user2);
        console2.log("User2 redemption completed");
        console2.log("Total requested amount after User2:", vault.totalRequestedAmount());
        console2.log("Total assets after User2:", vault.totalAssets());
        console2.log("Total shares after User2:", vault.totalSupply());
        vm.stopPrank();

        // Final state
        console2.log("\n=== FINAL STATE ===");
        console2.log("User1 shares:", vault.balanceOf(user1));
        console2.log("User2 shares:", vault.balanceOf(user2));
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());
        console2.log("Total requested amount:", vault.totalRequestedAmount());

        console2.log("=== Clean test_totalRequestedAmount completed ===");
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);

        console2.log("Exchange rate after yield:", vault.exchangeRate());
        console2.log("Total assets after yield:", vault.totalAssets());
        console2.log("Total shares after yield:", vault.totalSupply());
        console2.log("User1 shares after yield:", vault.balanceOf(user1));
        console2.log("User2 shares after yield:", vault.balanceOf(user2));

        // Phase 5: More deposits after yield
        console2.log("\n=== PHASE 5: More Deposits After Yield ===");

        // User1 deposits again
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT / 3, user1);
        console2.log("User1 deposited again:", DEPOSIT_AMOUNT / 3);
        console2.log("User1 total shares:", vault.balanceOf(user1));
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());

        // User2 deposits again
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT / 5, user2);
        console2.log("User2 deposited again:", DEPOSIT_AMOUNT / 5);
        console2.log("User2 total shares:", vault.balanceOf(user2));
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());

        // Phase 6: Second Yield Distribution
        console2.log("\n=== PHASE 6: Second Yield Distribution ===");

        _distributeYieldWithAssets(YIELD_AMOUNT / 2, FEE_AMOUNT / 2, 2, true);
        console2.log("Distributing yield:", (YIELD_AMOUNT / 2));
        // Wait for vesting period
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);

        console2.log("Exchange rate after second yield:", vault.exchangeRate());
        console2.log("Total assets after second yield:", vault.totalAssets());
        console2.log("Total shares after second yield:", vault.totalSupply());
        console2.log("User1 shares after second yield:", vault.balanceOf(user1));
        console2.log("User2 shares after second yield:", vault.balanceOf(user2));

        // Phase 7: Full redemptions
        console2.log("\n=== PHASE 7: Full Redemptions ===");

        uint256 user1FinalShares = vault.balanceOf(user1);
        uint256 user2FinalShares = vault.balanceOf(user2);

        // User1 requests full redemption
        uint256 user1FinalAssets = vault.previewRedeem(user1FinalShares);
        console2.log("User1 final shares to redeem:", user1FinalShares);
        console2.log("User1 final assets expected:", user1FinalAssets);

        vm.prank(user1);
        vault.requestRedeem(user1FinalShares);
        console2.log("User1 requested full redemption");
        console2.log("User1 remaining shares:", vault.balanceOf(user1));
        console2.log("Total assets after User1 full:", vault.totalAssets());
        console2.log("Total shares after User1 full:", vault.totalSupply());

        // User2 requests full redemption
        uint256 user2FinalAssets = vault.previewRedeem(user2FinalShares);
        console2.log("User2 final shares to redeem:", user2FinalShares);
        console2.log("User2 final assets expected:", user2FinalAssets);

        vm.prank(user2);
        vault.requestRedeem(user2FinalShares);
        console2.log("User2 requested full redemption");
        console2.log("User2 remaining shares:", vault.balanceOf(user2));
        console2.log("Total assets after User2 full:", vault.totalAssets());
        console2.log("Total shares after User2 full:", vault.totalSupply());

        // Phase 6: Execute full redemptions
        console2.log("\n=== PHASE 6: Execute Full Redemptions ===");

        // Transfer more assets to vault
        vm.startPrank(address(manager));
        asset.transfer(address(vault), asset.balanceOf(address(manager)));
        vm.stopPrank();

        // Execute User1 full redemption
        vm.startPrank(executor);
        console2.log("Executing User1 full redemption...");
        manager.redeemFor(address(vault), user1);
        console2.log("User1 full redemption completed");
        console2.log("Total requested amount after User1 full:", vault.totalRequestedAmount());
        console2.log("Total assets after User1 full execution:", vault.totalAssets());
        console2.log("Total shares after User1 full execution:", vault.totalSupply());

        // Execute User2 full redemption
        console2.log("Executing User2 full redemption...");
        manager.redeemFor(address(vault), user2);
        console2.log("User2 full redemption completed");
        console2.log("Total requested amount after User2 full:", vault.totalRequestedAmount());
        console2.log("Total assets after User2 full execution:", vault.totalAssets());
        console2.log("Total shares after User2 full execution:", vault.totalSupply());
        vm.stopPrank();

        // Final state
        console2.log("\n=== FINAL STATE ===");
        console2.log("User1 shares:", vault.balanceOf(user1));
        console2.log("User2 shares:", vault.balanceOf(user2));
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total shares:", vault.totalSupply());
        console2.log("Total requested amount:", vault.totalRequestedAmount());

        console2.log("=== Complex test_totalRequestedAmount completed ===");
    }

    function test_Pause() public {
        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
    }

    function test_ManagerIntegration_AssetManagement() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialShares = vault.balanceOf(treasury);

        ManageAssetAndShares memory order = ManageAssetAndShares({
            vaultToken: address(vault),
            shares: 10e6,
            assetAmount: 10e6,
            updateAsset: true,
            isMint: true
        });
        vm.startPrank(address(yield));
        manager.manageAssetAndShares(treasury, order);
        vm.stopPrank();

        uint256 assetsAfter = vault.totalAssets();
        uint256 sharesAfter = vault.balanceOf(treasury);

        assertEq(assetsAfter, initialAssets + 10e6, "Assets should be updated");
        assertEq(sharesAfter, initialShares + 10e6, "Shares should be minted to treasury");
    }

    function test_PausUnpause_ProtocolControl() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.pause();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.unpause();
        vm.stopPrank();

        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();
    }

    function test_ExchangeRate_UpdatesWithYield() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 initialRate = vault.exchangeRate();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        uint256 newRate = vault.exchangeRate();
        assertGe(newRate, initialRate, "Exchange rate should not decrease after yield");

        uint256 scaledRate = vault.exchangeRateScaled();
        assertGt(scaledRate, 0, "Scaled exchange rate should be positive");
    }

    function test_MultipleEpochs_YieldDistribution() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vault.exchangeRate();

        vm.warp(block.timestamp + 24 hours);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 2, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vault.exchangeRate();

        vm.warp(block.timestamp + 24 hours + 1);
        yield.distributeYield(YIELD_AMOUNT / 2, FEE_AMOUNT / 2, 3, false);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vault.exchangeRate();

        vm.expectRevert();
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);

        vm.stopPrank();
    }

    function test_AccessControl_AdminFunctions() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.pause();
        vm.stopPrank();

        vm.startPrank(admin);
        vault.pause();
        vault.unpause();
        vm.stopPrank();
    }

    function test_AccessControl_ExecutorFunctions() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 userShares = vault.balanceOf(user1);
        vault.requestRedeem(userShares);
        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);
        vm.stopPrank();

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        manager.redeemFor(address(vault), user1);
        vm.stopPrank();

        vm.startPrank(executor);
        manager.redeemFor(address(vault), user1);
        vm.stopPrank();

        (uint256 shares,,, bool exists) = vault.getRedeemRequest(user1);
        assertFalse(exists, "Withdrawal request should be removed after execution");
    }

    function test_0_Amounts() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(0, user1);
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        vm.expectRevert();
        yield.distributeYield(0, 0, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();
    }

    function test__WithdrawNoYield() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        // Request redemption - shares should be burned immediately
        vault.requestRedeem(vault.balanceOf(user1));

        // Check that shares are burned
        assertEq(vault.balanceOf(user1), 0, "Shares should be burned immediately on request");

        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);
        uint256 before = asset.balanceOf(user1);
        vm.stopPrank();

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(user1);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vault.redeem(requestShares, user1, user1);
        uint256 afterBal = asset.balanceOf(user1);
        assertGe(afterBal, before, "Should not lose assets");
        vm.stopPrank();
    }

    function test__Withdraw_with_Yield_NoFee() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        console2.log("Initial exchange rate (no fee):", vault.exchangeRate());
        console2.log("Treasury vault balance before yield (no fee):", vault.balanceOf(treasury));
        console2.log();

        _distributeYieldWithAssets(YIELD_AMOUNT, 0, 1, true);
        console2.log("Exchange rate after yield (no fee):", vault.exchangeRate());
        console2.log("Treasury vault balance after yield (no fee):", vault.balanceOf(treasury));
        console2.log();

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.stopPrank();
        uint256 userShares = vault.balanceOf(user1);
        console2.log("User shares before withdrawal request (no fee):", userShares);
        vm.startPrank(user1);

        vault.requestRedeem(userShares);
        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);

        uint256 before = asset.balanceOf(user1);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vault.redeem(requestShares, user1, user1);

        uint256 afterBal = asset.balanceOf(user1);
        assertGe(afterBal, before, "Should not lose assets");
        vm.stopPrank();
    }

    function test__Withdraw_with_Yield_WithFee() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        console2.log("Initial exchange rate (with fee):", vault.exchangeRate());
        console2.log("Treasury vault balance before yield (with fee):", vault.balanceOf(treasury));
        console2.log();

        _distributeYieldWithAssets(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        console2.log("Exchange rate after yield (with fee):", vault.exchangeRate());
        console2.log("Treasury vault balance after yield (with fee):", vault.balanceOf(treasury));
        console2.log();

        vm.startPrank(admin);
        asset.mint(address(vault), DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        vm.stopPrank();
        uint256 userShares = vault.balanceOf(user1);
        console2.log("User shares before withdrawal request (with fee):", userShares);
        vm.startPrank(user1);

        // Request redemption - shares should be burned immediately
        vault.requestRedeem(userShares);

        // Check that shares are burned
        assertEq(vault.balanceOf(user1), 0, "Shares should be burned immediately on request");

        vm.warp(block.timestamp + vault.cooldownPeriod() + 1);

        uint256 before = asset.balanceOf(user1);
        // Get the shares from redemption request since balance is now 0
        (uint256 requestShares,,,) = vault.getRedeemRequest(user1);
        vault.redeem(requestShares, user1, user1);

        uint256 afterBal = asset.balanceOf(user1);
        assertGe(afterBal, before, "Should not lose assets");
        vm.stopPrank();
    }

    function test_DistributeYield_TimeRestriction() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);

        vm.expectRevert();
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 2, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 24 hours);

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 2, true);
        vm.stopPrank();
    }

    function test_ProfitDistribution_MintsShares() public {
        // Initial setup - user deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Record initial state
        uint256 initialTreasuryShares = vault.balanceOf(treasury);
        uint256 initialTotalSupply = vault.totalSupply();

        console2.log("=== PROFIT DISTRIBUTION TEST ===");
        console2.log("Initial treasury shares:", initialTreasuryShares);
        console2.log("Initial total supply:", initialTotalSupply);
        console2.log("Initial exchange rate:", vault.exchangeRate());
        console2.log("Initial total assets:", vault.totalAssets());
        console2.log("Yield amount:", YIELD_AMOUNT);
        console2.log("Fee amount:", FEE_AMOUNT);
        console2.log();

        // Profit distribution - should mint shares to treasury
        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.stopPrank();

        uint256 treasurySharesAfterProfit = vault.balanceOf(treasury);
        uint256 totalSupplyAfterProfit = vault.totalSupply();

        console2.log("After profit distribution:");
        console2.log("Treasury shares:", treasurySharesAfterProfit);
        console2.log("Total supply:", totalSupplyAfterProfit);
        console2.log("Final exchange rate:", vault.exchangeRate());
        console2.log("Final total assets:", vault.totalAssets());
        console2.log("Shares minted to treasury:", treasurySharesAfterProfit - initialTreasuryShares);
        console2.log("Total supply increase:", totalSupplyAfterProfit - initialTotalSupply);
        console2.log();

        // Verify shares were minted to treasury during profit
        assertGt(treasurySharesAfterProfit, initialTreasuryShares, "Treasury should receive shares during profit");
        assertGt(totalSupplyAfterProfit, initialTotalSupply, "Total supply should increase during profit");

        // Calculate expected fee shares
        uint256 expectedFeeShares = vault.previewDeposit(FEE_AMOUNT);
        uint256 actualMintedShares = treasurySharesAfterProfit - initialTreasuryShares;
        assertApproxEqRel(actualMintedShares, expectedFeeShares, 0.01e18, "Fee shares should be minted correctly");
    }

    function test_LossDistribution_BurnsShares() public {
        // Initial setup - user deposits
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // First, do a profit distribution to ensure treasury has shares
        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.stopPrank();

        uint256 treasurySharesAfterProfit = vault.balanceOf(treasury);
        uint256 totalSupplyAfterProfit = vault.totalSupply();

        console2.log("=== LOSS DISTRIBUTION TEST ===");
        console2.log("Treasury shares before loss:", treasurySharesAfterProfit);
        console2.log("Total supply before loss:", totalSupplyAfterProfit);
        console2.log("Exchange rate before loss:", vault.exchangeRate());
        console2.log("Total assets before loss:", vault.totalAssets());
        console2.log();

        // Warp time to allow next distribution
        vm.warp(block.timestamp + 25 hours);

        // Loss distribution - should burn shares from treasury
        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT / 2, FEE_AMOUNT / 2, 2, false);
        vm.stopPrank();

        uint256 treasurySharesAfterLoss = vault.balanceOf(treasury);
        uint256 totalSupplyAfterLoss = vault.totalSupply();

        console2.log("After loss distribution:");
        console2.log("Treasury shares:", treasurySharesAfterLoss);
        console2.log("Total supply:", totalSupplyAfterLoss);
        console2.log("Final exchange rate:", vault.exchangeRate());
        console2.log("Final total assets:", vault.totalAssets());
        console2.log("Shares burned from treasury:", treasurySharesAfterProfit - treasurySharesAfterLoss);
        console2.log("Total supply decrease:", totalSupplyAfterProfit - totalSupplyAfterLoss);
        console2.log();

        // Verify shares were burned from treasury during loss
        assertLt(treasurySharesAfterLoss, treasurySharesAfterProfit, "Treasury shares should be burned during loss");
        assertLt(totalSupplyAfterLoss, totalSupplyAfterProfit, "Total supply should decrease during loss");

        // Calculate expected burned shares
        uint256 expectedBurnedShares = vault.previewDeposit(FEE_AMOUNT / 2);
        uint256 actualBurnedShares = treasurySharesAfterProfit - treasurySharesAfterLoss;
        assertApproxEqRel(actualBurnedShares, expectedBurnedShares, 0.01e18, "Fee shares should be burned correctly");
    }
}
