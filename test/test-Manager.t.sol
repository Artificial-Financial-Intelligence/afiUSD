// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {afiToken} from "../src/afiToken.sol";
import {Manager} from "../src/Manager.sol";
import {Yield} from "../src/Yield.sol";
import {afiProxy} from "../src/Proxy.sol";
import {IManager, ManageAssetAndShares} from "../src/Interface/IManager.sol";

contract ManagerTest is Test {
    MockERC20 public asset;
    afiToken public vault;
    Manager public manager;
    Yield public yield;

    // Mainnet addresses for fork tests
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AAVE_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address public constant AUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    address public admin = address(0x1);
    address public treasury = address(0x2);
    address public user1 = address(0x3);
    address public rebalancer = address(0x5);
    address public yieldRebalancer = address(0x6);
    address public executor = address(0x7);
    address public operator = address(0x8);

    uint256 public constant INITIAL_BALANCE = 10000e6;
    uint256 public constant DEPOSIT_AMOUNT = 1000e6;
    uint256 public cooldownPeriod = 24 hours;
    uint256 public vestingPeriod = 1 days;

    function setUp() public {
        vm.startPrank(admin);

        asset = new MockERC20("USDC", "USDC");

        // Deploy implementation contracts
        afiToken afiTokenImpl = new afiToken();
        Manager managerImpl = new Manager();
        Yield yieldImpl = new Yield();

        // Deploy Yield proxy
        bytes memory yieldInitData = abi.encodeWithSelector(
            Yield.initialize.selector,
            admin, // admin
            yieldRebalancer // rebalancer
        );
        afiProxy yieldProxy = new afiProxy(address(yieldImpl), yieldInitData);
        yield = Yield(address(yieldProxy));

        // Deploy Manager proxy
        bytes memory managerInitData = abi.encodeWithSelector(
            Manager.initialize.selector,
            admin, // admin
            address(yield), // yield
            executor // executor
        );
        afiProxy managerProxy = new afiProxy(address(managerImpl), managerInitData);
        manager = Manager(address(managerProxy));

        // Deploy afiToken proxy
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

        // Setup cross-references
        vm.startPrank(admin);
        manager.setTreasury(treasury);
        manager.setManagerAndYield(address(yield), address(vault));
        manager.setMinSharesInVaultToken(address(vault), 1e6);
        manager.setMaxRedeemCap(address(vault), type(uint256).max);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        yield.setManager(address(manager));
        vault.setFee(1e17);
        vm.stopPrank();

        // Fund treasury
        asset.mint(treasury, INITIAL_BALANCE);
        vm.prank(treasury);
        asset.transfer(address(manager), INITIAL_BALANCE);
    }

    // ============ PERMISSION TESTS ============

    function test_OnlyAdminCanSetTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        manager.setTreasury(user1);
    }

    function test_OnlyOperatorCanExecute() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(asset);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        vm.prank(user1);
        vm.expectRevert();
        manager.execute(targets, data);
    }

    function test_OnlyAdminOrSelfCanWithdrawAssets() public {
        vm.prank(user1);
        vm.expectRevert();
        manager.transferToVault(address(asset), 1000e6);
    }

    // ============ EXECUTE FUNCTION TESTS ============

    function test_ExecuteWithValidTargets() public {
        // First whitelist the asset address
        address[] memory wallets = new address[](1);
        bool[] memory statuses = new bool[](1);
        wallets[0] = address(asset);
        statuses[0] = true;

        vm.prank(admin);
        manager.setWhitelistedAddresses(wallets, statuses);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = address(asset);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        targets[1] = address(asset);
        data[1] = abi.encodeWithSelector(IERC20.totalSupply.selector);

        vm.prank(operator);
        bytes[] memory results = manager.execute(targets, data);
        assertEq(results.length, 2);
    }

    function test_ExecuteWithInvalidTarget() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(0x999);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        vm.prank(operator);
        vm.expectRevert();
        manager.execute(targets, data);
    }

    function test_ExecuteWithLengthMismatch() public {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(asset);
        targets[1] = address(asset);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        vm.prank(operator);
        vm.expectRevert();
        manager.execute(targets, data);
    }

    // ============ SECURITY PROTECTION TESTS ============

    function test_CannotWhitelistAfiToken() public {
        address[] memory wallets = new address[](1);
        bool[] memory statuses = new bool[](1);
        wallets[0] = address(vault);
        statuses[0] = true;

        vm.prank(admin);
        vm.expectRevert();
        manager.setWhitelistedAddresses(wallets, statuses);
    }

    function test_CannotWhitelistYield() public {
        address[] memory wallets = new address[](1);
        bool[] memory statuses = new bool[](1);
        wallets[0] = address(yield);
        statuses[0] = true;

        vm.prank(admin);
        vm.expectRevert();
        manager.setWhitelistedAddresses(wallets, statuses);
    }

    function test_CannotExecuteOnAfiToken() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(vault);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        vm.prank(operator);
        vm.expectRevert();
        manager.execute(targets, data);
    }

    function test_CannotExecuteOnYield() public {
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(yield);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));

        vm.prank(operator);
        vm.expectRevert();
        manager.execute(targets, data);
    }

    // ============ WITHDRAW ASSETS TESTS ============

    function test_AdminCanWithdrawAssets() public {
        uint256 initialBalance = asset.balanceOf(treasury);
        uint256 withdrawAmount = 1000e6;

        vm.prank(operator);
        manager.transferToVault(address(asset), withdrawAmount);

        assertEq(asset.balanceOf(manager.afiToken()), initialBalance + withdrawAmount);
    }

    // ============ CONFIGURATION TESTS ============

    function test_SetTreasury() public {
        address newTreasury = address(0x123);
        vm.prank(admin);
        manager.setTreasury(newTreasury);
        assertEq(manager.treasury(), newTreasury);
    }

    function test_SetManagerAndYield() public {
        address newYield = address(0x456);
        address newAfiToken = address(0x789);

        vm.prank(admin);
        manager.setManagerAndYield(newYield, newAfiToken);

        assertEq(manager.yield(), newYield);
        assertEq(manager.afiToken(), newAfiToken);
    }

    function test_SetWhitelistedAddresses() public {
        address[] memory wallets = new address[](2);
        bool[] memory statuses = new bool[](2);
        wallets[0] = user1;
        wallets[1] = address(0xABC);
        statuses[0] = true;
        statuses[1] = false;

        vm.prank(admin);
        manager.setWhitelistedAddresses(wallets, statuses);

        assertTrue(manager.whitelistedAddresses(user1));
        assertFalse(manager.whitelistedAddresses(address(0xABC)));
    }

    // ============ EDGE CASES AND FAILURE MODES ============

    function test_SetTreasuryWithZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        manager.setTreasury(address(0));
    }

    function test_SetManagerAndYieldWithZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        manager.setManagerAndYield(address(0), address(vault));
    }

    function test_SetMinSharesWithZero() public {
        vm.prank(admin);
        vm.expectRevert();
        manager.setMinSharesInVaultToken(address(vault), 0);
    }

    function test_WhitelistedAddressesLengthMismatch() public {
        address[] memory wallets = new address[](2);
        bool[] memory statuses = new bool[](1);
        wallets[0] = user1;
        wallets[1] = address(0xABC);
        statuses[0] = true;

        vm.prank(admin);
        vm.expectRevert();
        manager.setWhitelistedAddresses(wallets, statuses);
    }

    function test_ExecuteWithEmptyArrays() public {
        address[] memory targets = new address[](0);
        bytes[] memory data = new bytes[](0);

        vm.prank(operator);
        bytes[] memory results = manager.execute(targets, data);
        assertEq(results.length, 0);
    }

    // ============ INTEGRATION TESTS ============

    function test_CompleteWorkflow() public {
        // 1. Setup whitelisted address
        address[] memory wallets = new address[](1);
        bool[] memory statuses = new bool[](1);
        wallets[0] = address(asset);
        statuses[0] = true;

        vm.prank(admin);
        manager.setWhitelistedAddresses(wallets, statuses);

        // 2. Execute call to whitelisted address
        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = address(asset);
        data[0] = abi.encodeWithSelector(IERC20.balanceOf.selector, address(manager));

        vm.prank(operator);
        bytes[] memory results = manager.execute(targets, data);
        assertEq(results.length, 1);

        // 3. Withdraw assets
        uint256 withdrawAmount = 1000e6;
        vm.prank(operator);
        manager.transferToVault(address(asset), withdrawAmount);
    }
}
