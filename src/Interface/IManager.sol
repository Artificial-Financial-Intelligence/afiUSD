// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.20;

struct ManageAssetAndShares {
    address vaultToken;
    uint256 shares;
    uint256 assetAmount;
    bool updateAsset;
    bool isMint;
}

interface IManager {
    // ============ EVENTS ============
    event AssetAndShareManaged(
        address indexed caller,
        address indexed vaultToken,
        uint256 shares,
        uint256 assetAmount,
        bool updateAsset,
        bool isMint
    );
    event TreasurySet(address indexed admin, address indexed treasury);
    event MinSharesInVaultTokenSet(address indexed admin, address indexed afiUSD, uint256 minShares);
    event MaxRedeemCapSet(address indexed admin, address indexed afiUSD, uint256 maxRedeemCap);
    event ManagerSet(address indexed admin, address indexed manager);
    event YieldSet(address indexed admin, address indexed yield);
    event AfiTokenSet(address indexed admin, address indexed afiToken);
    event WhitelistUpdated(address indexed admin, address indexed wallet, bool status);
    event BatchExecuted(address indexed operator, address[] targets, bytes[] data);
    event RedemptionExecuted(address indexed operator, address indexed afiUSD, address indexed user);
    event AssetsWithdrawn(address indexed caller, address indexed recipient, address indexed asset, uint256 amount);

    // ============ FUNCTIONS ============
    function treasury() external view returns (address);
    function yield() external view returns (address);
    function afiToken() external view returns (address);
    function whitelistedAddresses(address) external view returns (bool);
    function minSharesInVaultToken(address) external view returns (uint256);
    function maxRedeemCap(address) external view returns (uint256);

    function setTreasury(address _treasury) external;
    function setManagerAndYield(address _yield, address _afiToken) external;
    function setWhitelistedAddresses(address[] calldata _wallets, bool[] calldata _statuses) external;
    function execute(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory results);
    function setMinSharesInVaultToken(address _afiUSD, uint256 _minShares) external;
    function setMaxRedeemCap(address _afiUSD, uint256 _maxRedeemCap) external;
    function manageAssetAndShares(address _to, ManageAssetAndShares memory _order) external;
    function redeemFor(address _afiUSD, address _user) external;
}
