// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import "openzeppelin-contracts/utils/math/Math.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IafiUSD} from "./Interface/IafiUSD.sol";
import {IManager} from "./Interface/IManager.sol";
import {Errors} from "./Errors.sol";

/**
 * @title afiToken
 * @dev ERC4626-compliant yield-bearing vault with withdrawal cooldown and yield vesting
 * @notice This contract implements a vault system with advanced withdrawal mechanisms
 * and yield distribution features. Users can deposit assets, earn yield, and withdraw with a
 * cooldown period to ensure orderly asset management.
 */
contract afiToken is
    Initializable,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IafiUSD
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ============ STRUCTS ============
    struct RedeemRequest {
        uint256 shares;
        uint256 assets;
        uint256 timestamp;
        bool exists;
    }

    // ============ CONSTRUCTOR ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ CONSTANTS ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant PRECISION = 1e18;
    uint256 constant HUNDRED_PERCENT = 100e18;
    uint256 constant ONE_PERCENT = 1e18;

    // ============ STATE VARIABLES ============
    uint256 public virtualAssets;
    uint256 public cooldownPeriod;
    uint256 public vestingAmount;
    uint256 public lastDistributionTimestamp;
    uint256 public vestingPeriod;
    uint256 public fee;
    address public manager;
    mapping(address => RedeemRequest) public redemptionRequests;
    uint256 public totalRequestedAmount;

    // ============ STORAGE GAP ============
    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;

    // ============ INITIALIZER ============
    /**
     * @dev Initializes the afiUSD vault contract
     * @param _name The name of the vault token
     * @param _symbol The symbol of the vault token
     * @param _asset The underlying asset token (e.g., USDC)
     * @param _admin Admin address with governance privileges
     * @param _manager Manager contract address for asset deployment
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        IERC20 _asset,
        address _admin,
        address _manager,
        uint256 _cooldownPeriod,
        uint256 _vestingPeriod
    ) public initializer {
        if (_admin == address(0)) revert Errors.InvalidAddress();
        if (_manager == address(0)) revert Errors.InvalidAddress();
        if (_cooldownPeriod > 7 days) revert Errors.InvalidCooldownPeriod();
        if (_vestingPeriod > 30 days) revert Errors.InvalidVestingPeriod();

        __ERC4626_init(_asset);
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        manager = _manager;
        cooldownPeriod = _cooldownPeriod;
        vestingPeriod = _vestingPeriod;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Required by the OZ UUPS module
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ EXTERNAL FUNCTIONS ============

    /**
     * @dev Request a redemption of shares. Shares are burned immediately when requested.
     * User must wait for cooldown period before executing the actual asset transfer.
     * @param shares Amount of shares to redeem
     */
    function requestRedeem(uint256 shares) external whenNotPaused {
        if (redemptionRequests[msg.sender].exists) revert Errors.RedemptionRequestAlreadyExists();
        if (shares == 0) revert Errors.ZeroAmount();
        if (balanceOf(msg.sender) < shares) revert Errors.InsufficientShares();

        uint256 assets = previewRedeem(shares);
        if (assets == 0) revert Errors.InsufficientAssets();

        uint256 maxRedeemCap = IManager(manager).maxRedeemCap(address(this));
        if (maxRedeemCap != 0 && assets > maxRedeemCap) {
            revert Errors.MaxRedeemCapExceeded();
        }
        // Burn shares immediately when redemption is requested
        _burn(msg.sender, shares);

        // Update virtual assets to reflect the burned shares
        _updateTotalAssets(assets, false);
        totalRequestedAmount += assets;

        // Store redemption request with burned shares and calculated assets
        redemptionRequests[msg.sender] =
            RedeemRequest({shares: shares, assets: assets, timestamp: block.timestamp, exists: true});
        emit RedemptionRequested(msg.sender, shares, assets, block.timestamp);
    }

    /**
     * @dev Check if a user can execute their redemption request
     * @param user Address to check
     * @return True if redemption can be executed
     */
    function canExecuteRedeem(address user) external view returns (bool) {
        RedeemRequest memory request = redemptionRequests[user];
        return request.exists && block.timestamp >= request.timestamp + cooldownPeriod;
    }

    /**
     * @dev Get redemption request for a user
     * @param user User address
     * @return shares Amount of shares requested
     * @return assets Amount of assets calculated
     * @return timestamp Request timestamp
     * @return exists Whether request exists
     */
    function getRedeemRequest(address user)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp, bool exists)
    {
        RedeemRequest memory request = redemptionRequests[user];
        return (request.shares, request.assets, request.timestamp, request.exists);
    }

    /**
     * @dev Get current exchange rate (shares per asset)
     * @return Exchange rate in basis points
     */
    function exchangeRate() external view returns (uint256) {
        return super.previewMint(PRECISION);
    }

    /**
     * @dev Get scaled exchange rate for 18 decimal precision
     * @return Scaled exchange rate
     */
    function exchangeRateScaled() public view returns (uint256) {
        uint256 exchangeRateInUnderlying = super.previewMint(PRECISION);
        return exchangeRateInUnderlying * 10 ** (18 - IERC20Metadata(asset()).decimals());
    }

    /**
     * @dev Set withdrawal cooldown period (admin only)
     * @param newPeriod New cooldown period in seconds (max 7 days)
     */
    function setCooldownPeriod(uint256 newPeriod) external onlyRole(ADMIN_ROLE) {
        if (newPeriod > 7 days) revert Errors.InvalidCooldownPeriod();
        cooldownPeriod = newPeriod;
        emit CooldownPeriodUpdated(newPeriod);
    }

    /**
     * @dev Pause all vault operations (admin only)
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
        emit Paused(msg.sender);
    }

    /**
     * @dev Unpause all vault operations (admin only)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Get current unvested amount
     * @return Unvested amount in underlying assets
     */
    function getUnvestedAmount() public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;
        if (timeSinceLastDistribution >= vestingPeriod) {
            return 0;
        }
        return ((vestingPeriod - timeSinceLastDistribution) * vestingAmount) / vestingPeriod;
    }

    /**
     * @dev Preview shares for deposit (includes fee calculation)
     * @param assets Amount of assets to deposit
     * @return Shares that would be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 sharesBeforeFee = super.previewDeposit(assets);
        uint256 feeShares = (sharesBeforeFee * fee) / HUNDRED_PERCENT;
        return sharesBeforeFee - feeShares;
    }

    /**
     * @dev Preview assets for mint (includes fee calculation)
     * @param shares Amount of shares to mint
     * @return Assets that would be required
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 grossShares = (shares * HUNDRED_PERCENT) / (HUNDRED_PERCENT - fee);
        return super.previewMint(grossShares);
    }

    /**
     * @dev Preview shares for withdrawal (includes fee calculation)
     * @param assets Amount of assets to withdraw
     * @return Shares that would be burned
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 sharesWithoutFee = super.previewWithdraw(assets);
        uint256 totalShares = (sharesWithoutFee * HUNDRED_PERCENT) / (HUNDRED_PERCENT - fee);
        return totalShares;
    }

    /**
     * @dev Preview assets for redeem (includes fee calculation)
     * @param shares Amount of shares to redeem
     * @return Assets that would be received
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 feeShares = (shares * fee) / HUNDRED_PERCENT;
        uint256 remainingShares = shares - feeShares;
        return super.previewRedeem(remainingShares);
    }

    /**
     * @dev Set the fee percentage for the vault (admin only)
     * @param newFee Fee percentage (max 1% = ONE_PERCENT)
     */
    function setFee(uint256 newFee) external onlyRole(ADMIN_ROLE) {
        if (newFee > ONE_PERCENT) revert Errors.InvalidFee();
        fee = newFee;
        emit FeeSet(msg.sender, newFee);
    }

    /**
     * @dev Set vesting period for yield distribution (admin only)
     * @param newPeriod New vesting period in seconds (max 30 days)
     */
    function setVestingPeriod(uint256 newPeriod) external onlyRole(ADMIN_ROLE) {
        if (newPeriod > 30 days) revert Errors.InvalidVestingPeriod();
        _updateVestingAmount(0);
        vestingPeriod = newPeriod;
        emit VestingPeriodUpdated(newPeriod);
    }

    /**
     * @dev Set manager contract address (admin only)
     * @param newManager New manager address
     */
    function setManager(address newManager) external onlyRole(ADMIN_ROLE) {
        if (newManager == address(0)) revert Errors.InvalidAddress();
        manager = newManager;
        emit ManagerUpdated(msg.sender, newManager);
    }

    /**
     * @dev Emergency recovery function to transfer stuck tokens or ETH back to the contract
     * @param token Address of the token to recover (address(0) for ETH)
     * @param amount Amount to recover
     * @param recipient Address to send recovered tokens/ETH to
     */
    function emergencyRecover(address token, uint256 amount, address recipient)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        if (recipient == address(0) || amount == 0) revert Errors.InvalidAddress();

        if (token == address(0)) {
            if (amount > address(this).balance) revert Errors.InsufficientBalance();
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert Errors.TransferFailed();
        } else {
            if (amount > IERC20(token).balanceOf(address(this))) revert Errors.InsufficientBalance();
            IERC20(token).safeTransfer(recipient, amount);
        }
        emit EmergencyRecovery(token, amount, recipient);
    }

    /**
     * @dev Transfer rewards from yield contract (yield contract only)
     * @param amount Amount of rewards to transfer
     * @param profit Whether this is a profit or loss
     */
    function transferInRewards(uint256 amount, bool profit) external override nonReentrant {
        if (msg.sender != IManager(manager).yield()) revert Errors.OnlyYieldContract();
        if (amount == 0) revert Errors.ZeroAmount();

        if (!profit) {
            _updateTotalAssets(amount, false);
            return;
        }

        _updateVestingAmount(amount);
        emit TransferRewards(msg.sender, amount);
    }

    /**
     * @dev Get total assets including unvested amounts
     * @return Total assets in underlying token
     */
    function totalAssets() public view virtual override returns (uint256) {
        return virtualAssets - getUnvestedAmount();
    }

    /**
     * @dev Update total assets (manager only)
     * @param amount Amount to add/subtract
     * @param add Whether to add (true) or subtract (false)
     */
    function updateTotalAssets(uint256 amount, bool add) external override {
        if (msg.sender != manager) revert Errors.OnlyManagerContract();
        _updateTotalAssets(amount, add);
    }

    /**
     * @dev Mint vault tokens (manager only)
     * @param to Recipient address
     * @param shares Amount of shares to mint
     */
    function mintVaultToken(address to, uint256 shares) external override {
        if (msg.sender != manager) revert Errors.OnlyManagerContract();
        // Security: Only allow minting to treasury to prevent unauthorized minting
        if (to != IManager(manager).treasury()) revert Errors.NotAuthorized();
        _mint(to, shares);
    }

    /**
     * @dev Burn vault tokens (manager only)
     * @param from Address to burn from
     * @param shares Amount of shares to burn
     */
    function burnVaultToken(address from, uint256 shares) external override {
        if (msg.sender != manager) revert Errors.OnlyManagerContract();
        // Security: Only allow burning from treasury to prevent unauthorized burning
        if (from != IManager(manager).treasury()) revert Errors.NotAuthorized();
        _burn(from, shares);
    }

    // ============ PUBLIC FUNCTIONS ============
    /**
     * @dev Withdraw assets with cooldown mechanism
     * @param assets Amount of assets to withdraw
     * @param receiver Recipient of assets
     * @param owner Owner of shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256 shares)
    {
        RedeemRequest memory request = redemptionRequests[owner];
        if (!request.exists) revert Errors.NoRedemptionRequest();
        if (block.timestamp < request.timestamp + cooldownPeriod) revert Errors.CooldownNotFinished();
        if (assets != request.assets) revert Errors.InvalidWithdrawalRequest();

        uint256 userAssets = request.assets;
        uint256 userShares = request.shares;
        if (userAssets == 0) revert Errors.InsufficientShares();

        _withdraw(msg.sender, receiver, owner, userAssets, userShares);

        return userShares;
    }

    /**
     * @dev Redeem shares with cooldown mechanism
     * @param shares Amount of shares to redeem
     * @param receiver Recipient of assets
     * @param owner Owner of shares
     * @return assets Amount of assets received
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256 assets)
    {
        RedeemRequest memory request = redemptionRequests[owner];
        if (!request.exists) revert Errors.NoRedemptionRequest();
        if (block.timestamp < request.timestamp + cooldownPeriod) revert Errors.CooldownNotFinished();
        if (shares != request.shares) revert Errors.InvalidWithdrawalRequest();

        uint256 userAssets = request.assets;
        uint256 userShares = request.shares;
        if (userAssets == 0) revert Errors.InsufficientShares();

        _withdraw(msg.sender, receiver, owner, userAssets, userShares);
        return userAssets;
    }

    /**
     * @dev Redeem shares on behalf of user (manager only) & NO-COOLDOWN PERIODS for RedeemFor() called by Manager only.
     * @param user User address
     */
    function redeemFor(address user) external whenNotPaused {
        if (msg.sender != manager) revert Errors.OnlyManagerContract();

        RedeemRequest memory request = redemptionRequests[user];
        if (!request.exists) revert Errors.NoRedemptionRequest();
        uint256 shares = request.shares;
        uint256 assets = request.assets;

        if (assets == 0) revert Errors.InsufficientShares();

        _withdraw(user, user, user, assets, shares);
        emit WithdrawalExecuted(user, shares, assets);
    }

    // ============ INTERNAL FUNCTIONS ============
    /**
     * @dev Update vesting amount for new yield distribution
     * @param newVestingAmount New amount to vest
     */
    function _updateVestingAmount(uint256 newVestingAmount) internal virtual {
        vestingAmount = newVestingAmount + getUnvestedAmount();
        _updateTotalAssets(newVestingAmount, true);
        lastDistributionTimestamp = block.timestamp;
    }

    /**
     * @dev Update total virtual assets
     * @param amount Amount to add/subtract
     * @param add Whether to add (true) or subtract (false)
     */
    function _updateTotalAssets(uint256 amount, bool add) internal {
        virtualAssets = add ? virtualAssets + amount : virtualAssets - amount;
        emit TotalAssetsUpdated(msg.sender, amount, add);
    }

    /**
     * @dev Override deposit function to include fee collection
     * @param caller Caller address
     * @param receiver Recipient address
     * @param assets Asset amount
     * @param shares Share amount
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        if (receiver == address(0) || assets == 0 || shares == 0) revert Errors.InvalidDeposit();
        if (shares < IManager(manager).minSharesInVaultToken(address(this))) revert Errors.InvalidMinShares();

        uint256 totalShares = super.previewDeposit(assets);
        uint256 feeShare = totalShares - shares;

        // Get treasury address from manager
        if (feeShare > 0) {
            address treasuryAddress = IManager(manager).treasury();
            _mint(treasuryAddress, feeShare);
        }

        _mint(receiver, shares);

        _updateTotalAssets(assets, true);
        IERC20(asset()).safeTransferFrom(caller, manager, assets);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Override withdraw function to include proper asset handling
     * @param caller Caller address
     * @param receiver Recipient address
     * @param owner Owner address
     * @param assets Asset amount
     * @param shares Share amount
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        if (receiver == address(0) || owner == address(0) || assets == 0 || shares == 0) {
            revert Errors.InvalidWithdrawal();
        }
        if (caller != owner) revert Errors.NotAuthorized();

        totalRequestedAmount -= assets;
        delete redemptionRequests[owner];
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 18 - IERC20Metadata(asset()).decimals();
    }
}
