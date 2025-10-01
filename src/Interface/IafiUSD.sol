// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.20;

interface IafiUSD {
    // ============ EVENTS ============
    event TransferRewards(address indexed caller, uint256 amount);
    event ManagerSet(address indexed caller, address indexed manager);
    event FeeSet(address indexed caller, uint256 fee);
    event YieldUpdated(uint256 newExchangeRate, uint256 timestamp);
    event CooldownPeriodUpdated(uint256 newPeriod);
    event RedemptionRequested(address indexed user, uint256 shares, uint256 assets, uint256 timestamp);
    event WithdrawalExecuted(address indexed user, uint256 shares, uint256 assets);
    event FeeConfigUpdated(uint256 depositFeeBps);
    event VestingPeriodUpdated(uint256 newPeriod);
    event YieldSet(address indexed caller, address indexed yield);
    event TotalAssetsUpdated(address indexed caller, uint256 amount, bool add);
    event EmergencyRecovery(address indexed token, uint256 amount, address indexed recipient);
    event ManagerUpdated(address indexed admin, address indexed manager);

    // ============ FUNCTIONS ============
    function transferInRewards(uint256 amount, bool profit) external;
    function exchangeRate() external view returns (uint256);
    function mintVaultToken(address to, uint256 amount) external;
    function burnVaultToken(address from, uint256 amount) external;
    function updateTotalAssets(uint256 amount, bool add) external;
    function fee() external view returns (uint256);
    function requestRedeem(uint256 shares) external;
    function canExecuteRedeem(address user) external view returns (bool);
    function getRedeemRequest(address user)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp, bool exists);
    function redemptionRequests(address user)
        external
        view
        returns (uint256 shares, uint256 assets, uint256 timestamp, bool exists);
    function exchangeRateScaled() external view returns (uint256);
    function setCooldownPeriod(uint256 newPeriod) external;
    function pause() external;
    function unpause() external;

    function setManager(address _manager) external;
    function redeemFor(address user) external;
    function emergencyRecover(address token, uint256 amount, address recipient) external;
}
