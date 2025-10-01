// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IafiUSD} from "./Interface/IafiUSD.sol";
import {IManager, ManageAssetAndShares} from "./Interface/IManager.sol";
import {Errors} from "./Errors.sol";

interface IYield {
    event DistributeYield(
        address caller, address indexed asset, address indexed receiver, uint256 amount, uint256 feeAmount, bool profit
    );
    event ManagerSet(address indexed caller, address indexed manager);
    event MinDistributionIntervalSet(address indexed admin, uint256 minDistributionInterval);
    event MaxYieldPercentageSet(address indexed admin, uint256 maxYieldPercentage);
    event MaxFeePercentage(address indexed admin, uint256 MaxFeePercentage);
}

/**
 * @title Yield
 * @dev Manages yield distribution and profit/loss accounting for vault contracts
 * @notice This contract handles the distribution of profits and losses to vault contracts
 * with vesting mechanisms and epoch-based distribution to prevent duplicates.
 */
contract Yield is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IYield {
    using SafeERC20 for IERC20;

    // ============ CONSTRUCTOR ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ CONSTANTS ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    // ============ STATE VARIABLES ============
    mapping(bytes32 => bool) public trxns;
    uint256 public epoch;
    uint256 public profit;
    uint256 public loss;
    uint256 public maxYieldPercentage;
    uint256 public maxFeePercentage;
    uint256 public lastDistributionTime;
    address public manager;

    // Minimum time between distributions
    uint256 public minDistributionInterval;

    // ============ STORAGE GAP ============
    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;

    // ============ INITIALIZER ============
    /**
     * @dev Initializes the Yield contract
     * @param _admin Admin address with governance privileges
     * @param _rebalancer Rebalancer address with yield distribution privileges
     */
    function initialize(address _admin, address _rebalancer) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REBALANCER_ROLE, _rebalancer);
        maxYieldPercentage = 50;
        maxFeePercentage = 5000;
        minDistributionInterval = 79200;
    }

    /**
     * @dev Required by the OZ UUPS module
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ EXTERNAL FUNCTIONS ============
    /**
     * @dev Get current epoch
     * @return Current epoch number
     */
    function getEpoch() external view returns (uint256) {
        return epoch;
    }

    /**
     * @dev Get last distribution time
     * @return Last distribution timestamp
     */
    function getLastDistributionTime() external view returns (uint256) {
        return lastDistributionTime;
    }

    /**
     * @dev Set minimum distribution interval (admin only)
     * @param _minDistributionInterval Minimum distribution interval
     */
    function setMinDistributionInterval(uint256 _minDistributionInterval) external onlyRole(ADMIN_ROLE) {
        if (_minDistributionInterval == 0) revert Errors.InvalidPeriod();
        minDistributionInterval = _minDistributionInterval;
        emit MinDistributionIntervalSet(msg.sender, _minDistributionInterval);
    }

    function setMaxYieldPercentage(uint256 _maxYieldPercentage) public onlyRole(ADMIN_ROLE) {
        if (_maxYieldPercentage == 0 || _maxYieldPercentage > 10_000) revert Errors.InvalidAmount();
        maxYieldPercentage = _maxYieldPercentage;
        emit MaxYieldPercentageSet(msg.sender, _maxYieldPercentage);
    }

    function setMaxFeePercentage(uint256 _maxFeePercent) public onlyRole(ADMIN_ROLE) {
        if (_maxFeePercent > 10_000) revert Errors.InvalidFee();
        maxFeePercentage = _maxFeePercent;
        emit MaxFeePercentage(msg.sender, _maxFeePercent);
    }

    /**
     * @dev Set manager contract address (admin only)
     * @param _manager New manager address
     */
    function setManager(address _manager) external onlyRole(ADMIN_ROLE) {
        if (_manager == address(0)) revert Errors.InvalidAddress();
        manager = _manager;
        emit ManagerSet(msg.sender, _manager);
    }

    /**
     * @dev Distribute yield to the vault (rebalancer only)
     * @param amount Amount of yield to distribute
     * @param feeAmount Fee amount to collect
     * @param nonce Sequential nonce to prevent duplicates
     * @param isProfit Whether this is a profit (true) or loss (false)
     */
    function distributeYield(uint256 amount, uint256 feeAmount, uint256 nonce, bool isProfit)
        external
        onlyRole(REBALANCER_ROLE)
    {
        uint256 totalAssets = IERC4626(getAFIToken()).totalAssets();
        require(amount <= (totalAssets * maxYieldPercentage / 10_000));
        require(feeAmount <= (amount * maxFeePercentage / 10_000));

        address vaultToken = IManager(manager).afiToken();
        if (nonce != epoch + 1) revert Errors.InvalidEpoch();

        bytes32 proofHash = keccak256(abi.encode(vaultToken, amount, nonce, isProfit));
        if (trxns[proofHash]) revert Errors.DuplicateTransaction();

        // Check if enough time has passed since last distribution
        if (lastDistributionTime > 0 && lastDistributionTime + minDistributionInterval > block.timestamp) {
            revert Errors.DistributionTooFrequent();
        }

        trxns[proofHash] = true;
        epoch = nonce;
        lastDistributionTime = block.timestamp;

        if (isProfit) {
            profit += amount;
            IafiUSD(vaultToken).transferInRewards(amount, true);

            if (feeAmount > 0) {
                uint256 feeShares = IERC4626(vaultToken).convertToShares(feeAmount);
                ManageAssetAndShares memory manageAssetAndShares = ManageAssetAndShares({
                    vaultToken: vaultToken,
                    shares: feeShares,
                    assetAmount: feeAmount,
                    updateAsset: true,
                    isMint: true
                });
                IManager(manager).manageAssetAndShares(IManager(manager).treasury(), manageAssetAndShares);
            }
        } else {
            loss += amount;
            IafiUSD(vaultToken).transferInRewards(amount, false);

            if (feeAmount > 0) {
                uint256 lossShares = IERC4626(vaultToken).convertToShares(feeAmount);
                ManageAssetAndShares memory manageAssetAndShares = ManageAssetAndShares({
                    vaultToken: vaultToken,
                    shares: lossShares,
                    assetAmount: feeAmount,
                    updateAsset: true,
                    isMint: false
                });
                IManager(manager).manageAssetAndShares(IManager(manager).treasury(), manageAssetAndShares);
            }
        }

        emit DistributeYield(msg.sender, IERC4626(vaultToken).asset(), vaultToken, amount, feeAmount, isProfit);
    }

    function getAFIToken() public view returns (address) {
        return IManager(manager).afiToken();
    }

    function getManager() public view returns (address) {
        return manager;
    }
}
