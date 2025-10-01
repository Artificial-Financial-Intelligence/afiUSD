// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IafiUSD} from "./Interface/IafiUSD.sol";
import {IManager, ManageAssetAndShares} from "./Interface/IManager.sol";
import {Errors} from "./Errors.sol";

/**
 * @title Manager
 * @dev Manages asset deployment across multiple DeFi protocols and coordinates with vault contracts
 * @notice This contract handles the deployment of user funds across various yield-generating protocols
 * and manages the coordination between the vault and yield contracts.
 */
contract Manager is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IManager {
    using SafeERC20 for IERC20;

    // ============ CONSTRUCTOR ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ CONSTANTS ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ STATE VARIABLES ============
    address public treasury;
    address public yield;
    address public afiToken;

    mapping(address => bool) public whitelistedAddresses;
    mapping(address => uint256) public minSharesInVaultToken;
    mapping(address => uint256) public maxRedeemCap;

    // ============ STORAGE GAP ============
    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;

    // ============ INITIALIZER ============
    /**
     * @dev Initializes the Manager contract
     * @param admin Admin address with governance privileges
     * @param _yield Yield contract address
     * @param _executor Executor address with operational privileges
     */
    function initialize(address admin, address _yield, address _executor) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, _executor);
        yield = _yield;
    }

    /**
     * @dev Required by the OZ UUPS module
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ EXTERNAL FUNCTIONS ============
    /**
     * @dev Set treasury address (admin only)
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        if (_treasury == address(0)) revert Errors.InvalidAddress();
        treasury = _treasury;
        emit TreasurySet(msg.sender, _treasury);
    }

    /**
     * @dev Set contract addresses (admin only)
     * @param _yield New yield address
     * @param _afiToken New afiToken address
     */
    function setManagerAndYield(address _yield, address _afiToken) external onlyRole(ADMIN_ROLE) {
        if (_yield == address(0)) revert Errors.InvalidAddress();
        if (_afiToken == address(0)) revert Errors.InvalidAddress();
        yield = _yield;
        afiToken = _afiToken;
        emit YieldSet(msg.sender, _yield);
        emit AfiTokenSet(msg.sender, _afiToken);
    }

    /**
     * @dev Set whitelisted addresses for external protocol interactions (admin only)
     * @param _wallets Array of wallet addresses to whitelist
     * @param _statuses Array of whitelist statuses (true = whitelisted, false = not whitelisted)
     */
    function setWhitelistedAddresses(address[] calldata _wallets, bool[] calldata _statuses)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_wallets.length != _statuses.length) revert Errors.LengthMismatch();
        for (uint256 i = 0; i < _wallets.length; i++) {
            // Security: Prevent whitelisting the afiToken and Yield
            if (_wallets[i] == afiToken || _wallets[i] == yield) revert Errors.NotWhitelisted();
            whitelistedAddresses[_wallets[i]] = _statuses[i];
            emit WhitelistUpdated(msg.sender, _wallets[i], _statuses[i]);
        }
    }

    /**
     * @dev Execute multiple calls to whitelisted external protocols (operator only)
     * @param targets Array of target contract addresses
     * @param data Array of call data for each target
     * @return results Array of return data from each call
     */
    function execute(address[] calldata targets, bytes[] calldata data)
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes[] memory results)
    {
        if (targets.length != data.length) revert Errors.LengthMismatch();
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            if (!whitelistedAddresses[targets[i]]) {
                revert Errors.NotWhitelisted();
            }
            (bool success, bytes memory result) = targets[i].call(data[i]);
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            results[i] = result;
        }
        emit BatchExecuted(msg.sender, targets, data);
        return results;
    }

    /**
     * @dev Redeem shares on behalf of a user (operator only)
     * @param _afiUSD Address of the afiUSD vault contract
     * @param _user User address to redeem for
     */
    function redeemFor(address _afiUSD, address _user) external onlyRole(OPERATOR_ROLE) {
        IafiUSD(_afiUSD).redeemFor(_user);
        emit RedemptionExecuted(msg.sender, _afiUSD, _user);
    }

    /**
     * @dev Set minimum shares required for vault token operations (admin only)
     * @param _afiUSD Address of the afiUSD vault contract
     * @param _minShares Minimum shares required
     */
    function setMinSharesInVaultToken(address _afiUSD, uint256 _minShares) external onlyRole(ADMIN_ROLE) {
        if (_minShares == 0) revert Errors.InvalidMinShares();
        minSharesInVaultToken[_afiUSD] = _minShares;
        emit MinSharesInVaultTokenSet(msg.sender, _afiUSD, _minShares);
    }

    /**
     * @dev Set maximum redeem cap for a vault (admin only)
     * @param _afiUSD Address of the afiUSD vault contract
     * @param _maxRedeemCap Maximum redeem cap
     */
    function setMaxRedeemCap(address _afiUSD, uint256 _maxRedeemCap) external onlyRole(ADMIN_ROLE) {
        maxRedeemCap[_afiUSD] = _maxRedeemCap;
        emit MaxRedeemCapSet(msg.sender, _afiUSD, _maxRedeemCap);
    }

    /**
     * @dev Manage assets and shares for a vault (yield contract only)
     * @param _to Recipient address for shares
     * @param _order Order containing asset and share management details
     */
    function manageAssetAndShares(address _to, ManageAssetAndShares memory _order) external {
        if (msg.sender != yield) revert Errors.OnlyYieldContract();

        if (_order.updateAsset) {
            IafiUSD(_order.vaultToken).updateTotalAssets(_order.assetAmount, _order.isMint);
        }
        if (_order.isMint) {
            IafiUSD(_order.vaultToken).mintVaultToken(_to, _order.shares);
        } else {
            IafiUSD(_order.vaultToken).burnVaultToken(_to, _order.shares);
        }
        emit AssetAndShareManaged(
            msg.sender, _order.vaultToken, _order.shares, _order.assetAmount, _order.updateAsset, _order.isMint
        );
    }

    function transferToVault(address token, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        IERC20(token).safeTransfer(afiToken, amount);
    }
}
