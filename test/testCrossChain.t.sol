// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IafiToken, IManager, IYield} from "./mock/interfaces.sol";
import {console2} from "forge-std/console2.sol";
import {afiToken} from "../src/afiToken.sol";
import {Manager} from "../src/Manager.sol";
import {Yield} from "../src/Yield.sol";
import {afiProxy} from "../src/Proxy.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";

contract forkTestDeployment is Test {
    afiToken public afiUSD;
    Manager public manager;
    Yield public yield;

    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address admin = 0xfa5b3614A7C8265E3e8c4f56bC123203BD155ff2;

    bytes32 public SALT = bytes32(uint256(12345));
    address create2Deployer = 0x2484D29cE8701d224C712481b46Ef82Ca5EA6C12;

    function setUp() public {}

    function testDeploymentETH() public {
        vm.createSelectFork("https://eth.merkle.io");
        vm.startPrank(create2Deployer);

        afiUSD = new afiToken();
        manager = new Manager();
        yield = new Yield();

        bytes memory initData = abi.encodeWithSelector(
            afiUSD.initialize.selector,
            "afiUSD",
            "afiUSD",
            usdc,
            admin,
            address(manager),
            1 days, // cooldownPeriod
            7 days // vestingPeriod
        );

        address proxyAddress = Create2.deploy(
            0, // value
            SALT,
            abi.encodePacked(type(afiProxy).creationCode, abi.encode(address(afiUSD), initData))
        );
        afiProxy afiUSDProxy = afiProxy(payable(proxyAddress));

        vm.stopPrank();
        console2.log("ETH Deployment:", address(afiUSDProxy));

        address predictedAddress = computeCreate2Address();
        console2.log("Predicted address:", predictedAddress);
    }

    function testDeploymentKatana() public {
        vm.createSelectFork("https://rpc.katana.network");
        vm.startPrank(create2Deployer);
        afiUSD = new afiToken();
        manager = new Manager();
        yield = new Yield();

        bytes memory initData = abi.encodeWithSelector(
            afiUSD.initialize.selector,
            "afiUSD",
            "afiUSD",
            usdc,
            admin,
            address(manager),
            1 days, // cooldownPeriod
            7 days // vestingPeriod
        );

        address proxyAddress = Create2.deploy(
            0, // value
            SALT,
            abi.encodePacked(type(afiProxy).creationCode, abi.encode(address(afiUSD), initData))
        );
        // Cast to address first to avoid payable fallback issue
        afiProxy afiUSDProxy = afiProxy(payable(proxyAddress));

        vm.stopPrank();
        console2.log(address(afiUSDProxy));

        address predictedAddress = computeCreate2Address();
        console2.log("Predicted address:", predictedAddress);
    }

    function computeCreate2Address() public view returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            afiUSD.initialize.selector,
            "afiUSD",
            "afiUSD",
            usdc,
            admin,
            address(manager),
            1 days, // cooldownPeriod
            7 days // vestingPeriod
        );

        bytes memory constructorData = abi.encode(address(afiUSD), initData);
        bytes memory creationCode = abi.encodePacked(type(afiProxy).creationCode, constructorData);

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), create2Deployer, SALT, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }
}
