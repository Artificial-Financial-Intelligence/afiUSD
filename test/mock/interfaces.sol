// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IafiToken {
    function ADMIN_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function PRECISION() external view returns (uint256);
    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function burnVaultToken(address from, uint256 shares) external;
    function canExecuteRedeem(address user) external view returns (bool);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function cooldownPeriod() external view returns (uint256);
    function decimals() external view returns (uint8);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function emergencyRecover(address token, uint256 amount, address recipient) external;
    function exchangeRate() external view returns (uint256);
    function exchangeRateScaled() external view returns (uint256);
    function fee() external view returns (uint256);
    function getRedeemRequest(address user)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp, bool exists);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getUnvestedAmount() external view returns (uint256);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        address _admin,
        address _manager,
        uint256 _cooldownPeriod,
        uint256 _vestingPeriod
    ) external;
    function lastDistributionTimestamp() external view returns (uint256);
    function manager() external view returns (address);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function mintVaultToken(address to, uint256 shares) external;
    function name() external view returns (string memory);
    function pause() external;
    function paused() external view returns (bool);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function proxiableUUID() external view returns (bytes32);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function redeemFor(address user) external;
    function redemptionRequests(address)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp, bool exists);
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function requestRedeem(uint256 shares) external;
    function revokeRole(bytes32 role, address account) external;
    function setCooldownPeriod(uint256 newPeriod) external;
    function setFee(uint256 newFee) external;
    function setManager(address newManager) external;
    function setVestingPeriod(uint256 newPeriod) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256);
    function totalRequestedAmount() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transferInRewards(uint256 amount, bool profit) external;
    function unpause() external;
    function updateTotalAssets(uint256 amount, bool add) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
    function vestingAmount() external view returns (uint256);
    function vestingPeriod() external view returns (uint256);
    function virtualAssets() external view returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}

interface IManager {
    struct ManageAssetAndShares {
        address vaultToken;
        uint256 shares;
        uint256 assetAmount;
        bool updateAsset;
        bool isMint;
    }

    function ADMIN_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function OPERATOR_ROLE() external view returns (bytes32);
    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
    function afiToken() external view returns (address);
    function execute(address[] memory targets, bytes[] memory data) external returns (bytes[] memory results);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(address admin, address _yield, address _executor) external;
    function manageAssetAndShares(address _to, ManageAssetAndShares memory _order) external;
    function maxRedeemCap(address) external view returns (uint256);
    function minSharesInVaultToken(address) external view returns (uint256);
    function proxiableUUID() external view returns (bytes32);
    function redeemFor(address _afiUSD, address _user) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function revokeRole(bytes32 role, address account) external;
    function setManagerAndYield(address _yield, address _afiToken) external;
    function setMaxRedeemCap(address _afiUSD, uint256 _maxRedeemCap) external;
    function setMinSharesInVaultToken(address _afiUSD, uint256 _minShares) external;
    function setTreasury(address _treasury) external;
    function setWhitelistedAddresses(address[] memory _wallets, bool[] memory _statuses) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferToVault(address token, uint256 amount) external;
    function treasury() external view returns (address);
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
    function whitelistedAddresses(address) external view returns (bool);
    function yield() external view returns (address);
}

interface IYield {
    function ADMIN_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function REBALANCER_ROLE() external view returns (bytes32);
    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);
    function distributeYield(uint256 amount, uint256 feeAmount, uint256 nonce, bool isProfit) external;
    function epoch() external view returns (uint256);
    function getAFIToken() external view returns (address);
    function getEpoch() external view returns (uint256);
    function getLastDistributionTime() external view returns (uint256);
    function getManager() external view returns (address);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(address _admin, address _rebalancer) external;
    function lastDistributionTime() external view returns (uint256);
    function loss() external view returns (uint256);
    function manager() external view returns (address);
    function minDistributionInterval() external view returns (uint256);
    function profit() external view returns (uint256);
    function proxiableUUID() external view returns (bytes32);
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function revokeRole(bytes32 role, address account) external;
    function setManager(address _manager) external;
    function setMinDistributionInterval(uint256 _minDistributionInterval) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function trxns(bytes32) external view returns (bool);
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
