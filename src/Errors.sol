// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Errors
 * @dev Shared custom errors for the afiUSD project
 * @notice This library contains all custom errors used across the project
 * to ensure consistency and reduce deployment costs
 */
library Errors {
    // ============ ACCESS CONTROL ERRORS ============
    error AccessDenied();
    error NotAuthorized();
    error NotWhitelisted();
    error OnlyYieldContract();
    error OnlyManagerContract();

    // ============ VALIDATION ERRORS ============
    error InvalidAddress();
    error InvalidAmount();
    error ZeroAmount();
    error InvalidFee();
    error InvalidPeriod();
    error InvalidCooldownPeriod();
    error InvalidVestingPeriod();
    error InvalidEpoch();
    error DuplicateTransaction();
    error LengthMismatch();
    error InvalidMinShares();
    error VaultAlreadyRegistered();
    error VaultNotRegistered();
    error MaxRedeemCapExceeded();

    // ============ VAULT OPERATION ERRORS ============
    error InsufficientShares();
    error InsufficientAssets();
    error InsufficientBalance();
    error NoRedemptionRequest();
    error CooldownNotFinished();
    error InvalidWithdrawalRequest();
    error InvalidDeposit();
    error InvalidWithdrawal();
    error InvalidRedeem();
    error InvalidMint();
    error TransferFailed();
    error RedemptionRequestAlreadyExists();

    // ============ STATE ERRORS ============
    error AlreadyInitialized();
    error NotInitialized();
    error Paused();
    error NotPaused();
    error InvalidState();

    // ============ YIELD DISTRIBUTION ERRORS ============
    error DistributionTooFrequent();
}
