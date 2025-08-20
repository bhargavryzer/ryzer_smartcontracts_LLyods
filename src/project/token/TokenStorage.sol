// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../compliance/ICompliance.sol";
import "../registry/interface/IIdentityRegistry.sol";

contract TokenStorage {
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant PROJECT_ADMIN_ROLE = keccak256("PROJECT_ADMIN_ROLE");
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev ERC20 basic variables
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;
    uint256 public maxSupply;

    /// @dev Token information
    string internal _tokenName;
    string internal _tokenSymbol;
    uint8 internal _tokenDecimals;
    address internal _tokenOnchainID;
    string internal constant _TOKEN_VERSION = "1.0.0";

    /// @dev Variables of freeze and pause functions
    mapping(address => bool) internal _frozen;
    mapping(address => uint256) internal _frozenTokens;

    bool internal _tokenPaused = false;

    /// @dev Identity Registry contract used by the onchain validator system
    IIdentityRegistry internal _tokenIdentityRegistry;

    /// @dev Compliance contract linked to the onchain validator system
    ICompliance internal _tokenCompliance;
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[49] private __gap;
}
