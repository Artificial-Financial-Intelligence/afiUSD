// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {afiToken} from "../src/afiToken.sol";
import {Manager} from "../src/Manager.sol";
import {Yield} from "../src/Yield.sol";
import {afiProxy} from "../src/Proxy.sol";
import {IManager, ManageAssetAndShares} from "../src/Interface/IManager.sol";

contract UpgradeTest is Test {
    MockERC20 public asset;
    afiToken public vault;
    Manager public manager;
    Yield public yield;

    address public admin = address(0x1);
    address public treasury = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public rebalancer = address(0x5);
    address public yieldRebalancer = address(0x6);
    address public executor = address(0x7);

    uint256 public constant INITIAL_BALANCE = 10000e6;
    uint256 public constant DEPOSIT_AMOUNT = 1000e6;
    uint256 public constant YIELD_AMOUNT = 5e6;
    uint256 public constant FEE_AMOUNT = 1e6;
    uint256 public cooldownPeriod = 24 hours;
    uint256 public vestingPeriod = 1 days;

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

        // Set up cross-references
        vm.startPrank(admin);
        yield.setManager(address(manager));
        manager.setTreasury(treasury);
        manager.setManagerAndYield(address(yield), address(vault));
        manager.setMinSharesInVaultToken(address(vault), 1e6);
        manager.setMaxRedeemCap(address(vault), type(uint256).max);
        yield.grantRole(yield.REBALANCER_ROLE(), yieldRebalancer);
        vm.stopPrank();

        // Fund users
        asset.mint(user1, INITIAL_BALANCE);
        asset.mint(user2, INITIAL_BALANCE);
        asset.mint(yieldRebalancer, INITIAL_BALANCE);
        asset.mint(treasury, INITIAL_BALANCE);
        asset.mint(address(manager), INITIAL_BALANCE * 2);

        // Approve vault to spend tokens
        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_Upgrade_afiUSD_Implementation() public {
        // Setup initial state
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 initialBalance = vault.balanceOf(user1);
        uint256 initialTotalAssets = vault.totalAssets();

        // Deploy new implementation
        afiToken newAfiTokenImpl = new afiToken();

        vm.startPrank(admin);
        vault.upgradeToAndCall(address(newAfiTokenImpl), "");
        vm.stopPrank();

        // Verify state is preserved
        assertEq(vault.balanceOf(user1), initialBalance, "User balance should be preserved after upgrade");
        assertEq(vault.totalAssets(), initialTotalAssets, "Total assets should be preserved after upgrade");

        // Verify functionality still works
        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        assertGt(vault.totalAssets(), initialTotalAssets, "Yield distribution should work after upgrade");
    }

    function test_Upgrade_Manager_Implementation() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        Manager newManagerImpl = new Manager();

        vm.startPrank(admin);
        manager.upgradeToAndCall(address(newManagerImpl), "");
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        assertGt(vault.totalAssets(), DEPOSIT_AMOUNT, "Yield distribution should still work after upgrade");
    }

    function test_Upgrade_Yield_Implementation() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        Yield newYieldImpl = new Yield();

        vm.startPrank(admin);
        yield.upgradeToAndCall(address(newYieldImpl), "");
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        assertGt(vault.totalAssets(), DEPOSIT_AMOUNT, "Yield distribution should still work after upgrade");
    }

    function test_Upgrade_All_Contracts_Sequence() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 initialBalance = vault.balanceOf(user1);
        uint256 initialTotalAssets = vault.totalAssets();

        afiToken newAfiTokenImpl = new afiToken();
        Manager newManagerImpl = new Manager();
        Yield newYieldImpl = new Yield();

        vm.startPrank(admin);
        yield.upgradeToAndCall(address(newYieldImpl), "");
        manager.upgradeToAndCall(address(newManagerImpl), "");
        vault.upgradeToAndCall(address(newAfiTokenImpl), "");
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), initialBalance, "User balance should be preserved after all upgrades");
        assertGt(vault.totalAssets(), initialTotalAssets, "Yield distribution should work after all upgrades");
    }

    function test_Upgrade_Security_OnlyAdmin() public {
        afiToken newAfiUSDImpl = new afiToken();
        vm.startPrank(user1);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newAfiUSDImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_State_Preservation() public {
        // Setup complex state
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vault.requestRedeem(vault.balanceOf(user1));
        vm.stopPrank();

        vm.startPrank(user2);
        vault.deposit(DEPOSIT_AMOUNT * 2, user2);
        vm.stopPrank();

        vm.startPrank(yieldRebalancer);
        yield.distributeYield(YIELD_AMOUNT, FEE_AMOUNT, 1, true);
        vm.warp(block.timestamp + vault.vestingPeriod() + 1);
        vm.stopPrank();

        // Capture state before upgrade
        uint256 user1Balance = vault.balanceOf(user1);
        uint256 user2Balance = vault.balanceOf(user2);
        uint256 totalAssets = vault.totalAssets();
        (uint256 shares, uint256 assets, uint256 timestamp, bool exists) = vault.getRedeemRequest(user1);

        // Deploy new implementation
        afiToken newAfiUSDImpl = new afiToken();

        vm.startPrank(admin);
        vault.upgradeToAndCall(address(newAfiUSDImpl), "");

        // Verify all state is preserved
        assertEq(vault.balanceOf(user1), user1Balance, "User1 balance should be preserved");
        assertEq(vault.balanceOf(user2), user2Balance, "User2 balance should be preserved");
        assertEq(vault.totalAssets(), totalAssets, "Total assets should be preserved");

        (uint256 sharesAfter, uint256 assetsAfter, uint256 timestampAfter, bool existsAfter) =
            vault.getRedeemRequest(user1);
        assertEq(sharesAfter, shares, "Withdrawal request shares should be preserved");
        assertEq(timestampAfter, timestamp, "Withdrawal request timestamp should be preserved");
        assertEq(existsAfter, exists, "Withdrawal request existence should be preserved");

        vm.stopPrank();
    }

    function test_Upgrade_With_Non_Admin() public {
        vm.startPrank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Deploy new implementation (could have new features)
        afiToken newAfiUSDImpl = new afiToken();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newAfiUSDImpl), "");
        vm.stopPrank();
    }
}
