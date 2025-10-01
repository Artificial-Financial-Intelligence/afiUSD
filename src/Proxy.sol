// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title afiProxy
 * @dev ERC1967 proxy for UUPS upgradeable contracts
 * @notice This proxy allows contracts to be upgraded while maintaining state
 * using the UUPS (Universal Upgradeable Proxy Standard) pattern
 */
contract afiProxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {}
}
